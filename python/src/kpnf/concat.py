"""Compose representation blocks: align by id, prefix columns per block, scale."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import polars as pl

from kpnf.io import KpnfError, read_table, split_matrix, write_table
from kpnf.provenance import Recorder

SCALINGS = ("none", "standard", "block")
ALIGNMENTS = ("strict", "partial")
# Columns that Ruddy adds to its projection tables and that are not features.
NON_FEATURE_COLUMNS = ("source_row_index",)


def _scale(x: np.ndarray, scaling: str, block: str) -> np.ndarray:
    if scaling == "none":
        return x
    std = x.std(axis=0, ddof=1) if x.shape[0] > 1 else np.zeros(x.shape[1])
    zero = np.where(std == 0)[0]
    if zero.size:
        raise KpnfError(
            f"block {block!r}: {zero.size} column(s) have zero variance and cannot be standardised; "
            "run selection on this block or use scaling: none"
        )
    z = (x - x.mean(axis=0)) / std
    if scaling == "block":
        # Equal total variance per block, so a 300-column block does not outweigh a 10-column one.
        z /= np.sqrt(x.shape[1])
    return z


def concat_blocks(
    blocks: list[tuple[str, str | Path]],
    out: str | Path,
    *,
    id_column: str = "id",
    scaling: str = "standard",
    alignment: str = "strict",
    separator: str = "__",
) -> dict:
    if scaling not in SCALINGS:
        raise KpnfError(f"scaling must be one of {', '.join(SCALINGS)}")
    if alignment not in ALIGNMENTS:
        raise KpnfError(f"alignment must be one of {', '.join(ALIGNMENTS)}")
    names = [name for name, _ in blocks]
    if len(blocks) < 2:
        raise KpnfError("a composition needs at least two blocks")
    if len(set(names)) != len(names):
        raise KpnfError(f"duplicated block names: {names}")
    recorder = Recorder(
        "concat",
        {
            "blocks": names,
            "id_column": id_column,
            "scaling": scaling,
            "alignment": alignment,
            "separator": separator,
        },
    )

    loaded = []
    for name, path in blocks:
        df = read_table(path)
        df = df.drop([c for c in NON_FEATURE_COLUMNS if c in df.columns])
        ids, features, x = split_matrix(df, id_column, source=f"block {name!r} ({path})")
        if not np.isfinite(x).all():
            bad = int((~np.isfinite(x)).any(axis=0).sum())
            raise KpnfError(
                f"block {name!r}: {bad} column(s) contain missing or non-finite values; "
                "KaleidoProt does not impute or zero-fill. Filter them with selection (max_missing: 0)."
            )
        loaded.append((name, ids, features, x))

    id_sets = [set(ids) for _, ids, _, _ in loaded]
    common = set.intersection(*id_sets)
    dropped = {name: sorted(set(ids) - common) for name, ids, _, _ in loaded if set(ids) - common}
    if dropped and alignment == "strict":
        detail = "; ".join(
            f"{n}: {len(v)} id(s) not in every block (e.g. {', '.join(v[:3])})" for n, v in dropped.items()
        )
        raise KpnfError(
            f"blocks do not share the same ids ({detail}). Use alignment: partial to keep the intersection."
        )
    if not common:
        raise KpnfError("blocks share no ids")

    # Row order follows the first block.
    order = [i for i in loaded[0][1] if i in common]
    parts, columns, block_map = [], [], []
    for name, ids, features, x in loaded:
        pos = {v: k for k, v in enumerate(ids)}
        aligned = x[[pos[i] for i in order]]
        parts.append(_scale(aligned, scaling, name))
        start = len(columns)
        columns.extend(f"{name}{separator}{f}" for f in features)
        block_map.append(
            {
                "block": name,
                "n_features": len(features),
                "first_column": start,
                "last_column": len(columns) - 1,
            }
        )

    matrix = np.hstack(parts)
    out_df = pl.DataFrame({id_column: order}).hstack(pl.DataFrame(matrix, schema=columns, orient="row"))
    write_table(out_df, out)
    blocks_json = Path(out).with_suffix(".blocks.json")
    summary = {
        "n_rows": len(order),
        "n_cols": len(columns),
        "blocks": block_map,
        "dropped_ids": dropped,
        "scaling": scaling,
        "alignment": alignment,
    }
    blocks_json.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    recorder.write(
        out,
        inputs=[p for _, p in blocks],
        outputs=[(out, {"n_rows": len(order), "n_cols": len(columns)}), (blocks_json, {})],
        extensions={"blocks": block_map, "n_dropped_ids": sum(len(v) for v in dropped.values())},
    )
    return summary
