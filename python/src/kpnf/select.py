"""Unsupervised feature filtering of one representation block, driven by its Ruddy EDA.

Ruddy deliberately never drops features, so the decision lives here. The criteria follow the
unsupervised defaults of ``krenai_pipelines/pipeline_feature_selection`` (missingness, constant and
near-constant columns, direct greedy redundancy on |rho|) so both pipelines report comparable panels.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np
import polars as pl

from kpnf.io import KpnfError, read_table, split_matrix, write_table
from kpnf.provenance import Recorder


@dataclass(frozen=True)
class SelectionSettings:
    max_missing: float = 0.0
    near_constant: float = 0.99
    abs_rho: float = 0.90
    method: str = "spearman"
    max_features: int | None = None

    def validate(self) -> None:
        if not 0 <= self.max_missing < 1:
            raise KpnfError("max_missing must be in [0, 1)")
        if not 0 < self.near_constant <= 1:
            raise KpnfError("near_constant must be in (0, 1]")
        if not 0 < self.abs_rho <= 1:
            raise KpnfError("abs_rho must be in (0, 1]")
        if self.method not in {"spearman", "pearson"}:
            raise KpnfError("method must be spearman or pearson")
        if self.max_features is not None and self.max_features < 1:
            raise KpnfError("max_features must be a positive integer")


def _rank(column: np.ndarray) -> np.ndarray:
    """Average ranks of the finite values; non-finite entries stay NaN."""
    out = np.full(column.shape, np.nan)
    finite = np.isfinite(column)
    values = column[finite]
    if values.size:
        _, inverse, counts = np.unique(values, return_inverse=True, return_counts=True)
        upper = np.cumsum(counts)
        out[finite] = ((upper - counts + 1 + upper) / 2.0)[inverse]
    return out


def _abs_corr(matrix: np.ndarray, method: str) -> np.ndarray:
    data = np.column_stack([_rank(matrix[:, j]) for j in range(matrix.shape[1])]) if method == "spearman" else matrix
    data = data.astype(float, copy=True)
    # Missing cells (only possible when max_missing > 0) take the column mean for this estimate only;
    # the output matrix keeps them as missing.
    col_mean = np.nanmean(data, axis=0)
    rows, cols = np.where(~np.isfinite(data))
    data[rows, cols] = col_mean[cols]
    data -= data.mean(axis=0)
    norms = np.linalg.norm(data, axis=0)
    norms[norms == 0] = 1.0
    data /= norms
    return np.abs(data.T @ data)


def _mode_fraction(column: np.ndarray) -> float:
    finite = column[np.isfinite(column)]
    if finite.size == 0:
        return 1.0
    _, counts = np.unique(finite, return_counts=True)
    return float(counts.max() / finite.size)


def _load_eda(eda_dir: Path) -> pl.DataFrame:
    columns_csv = eda_dir / "columns.csv"
    if not columns_csv.is_file():
        raise KpnfError(f"{eda_dir}: columns.csv not found; expected the output of `ruddy inspect univariate`")
    eda = pl.read_csv(columns_csv).select("column", "missing_fraction", "is_constant")
    stats_csv = eda_dir / "numeric_statistics.csv"
    if stats_csv.is_file():
        stats = pl.read_csv(stats_csv).select("column", pl.col("variance").cast(pl.Float64, strict=False))
        eda = eda.join(stats, on="column", how="left")
    else:
        eda = eda.with_columns(pl.lit(None, dtype=pl.Float64).alias("variance"))
    return eda


def select_block(
    matrix_path: str | Path,
    eda_dir: str | Path,
    out: str | Path,
    report: str | Path,
    *,
    id_column: str = "id",
    settings: SelectionSettings,
) -> dict:
    settings.validate()
    recorder = Recorder("select", {"id_column": id_column, **asdict(settings)})
    df = read_table(matrix_path)
    ids, features, x = split_matrix(df, id_column, source=str(matrix_path))
    eda = _load_eda(Path(eda_dir))
    known = set(eda.get_column("column").to_list())
    missing_in_eda = [f for f in features if f not in known]
    if missing_in_eda:
        raise KpnfError(
            f"{eda_dir}: EDA does not describe {len(missing_in_eda)} feature(s) of {matrix_path} "
            f"(e.g. {', '.join(missing_in_eda[:5])}); was it computed on this matrix?"
        )
    info = {r["column"]: r for r in eda.iter_rows(named=True)}

    rows: list[dict] = []
    candidates: list[int] = []
    for j, name in enumerate(features):
        r = info[name]
        row = {
            "feature": name,
            "missing_fraction": r["missing_fraction"],
            "variance": r["variance"],
            "mode_fraction": None,
            "status": "dropped",
            "reason": "",
            "redundant_with": None,
            "abs_rho": None,
        }
        if r["missing_fraction"] is not None and r["missing_fraction"] > settings.max_missing:
            row["reason"] = "missing"
        elif r["is_constant"]:
            row["reason"] = "constant"
        else:
            row["mode_fraction"] = _mode_fraction(x[:, j])
            if row["mode_fraction"] >= settings.near_constant:
                row["reason"] = "near_constant"
            else:
                candidates.append(j)
        rows.append(row)

    # Highest variance first, ties by name, so the greedy pass is deterministic.
    candidates.sort(key=lambda j: (-(rows[j]["variance"] or 0.0), features[j]))
    kept: list[int] = []
    if candidates:
        corr = _abs_corr(x[:, candidates], settings.method)
        kept_pos: list[int] = []
        for pos, j in enumerate(candidates):
            if kept_pos:
                worst = int(np.argmax(corr[pos, kept_pos]))
                rho = float(corr[pos, kept_pos[worst]])
                if rho > settings.abs_rho:
                    rows[j].update(reason="redundant", redundant_with=features[candidates[kept_pos[worst]]],
                                   abs_rho=round(rho, 6))
                    continue
            if settings.max_features is not None and len(kept_pos) >= settings.max_features:
                rows[j]["reason"] = "max_features"
                continue
            kept_pos.append(pos)
            rows[j]["status"] = "kept"
        kept = [candidates[p] for p in kept_pos]
    if not kept:
        raise KpnfError(f"{matrix_path}: no feature survived selection; relax the thresholds")

    kept_names = [features[j] for j in sorted(kept)]  # keep the original column order in the output
    out_df = df.select(pl.col(id_column).cast(pl.String), *kept_names)
    write_table(out_df, out)
    report_df = pl.DataFrame(rows, infer_schema_length=None)
    write_table(report_df, report)
    counts = report_df.group_by("reason").len().sort("reason")
    summary = {
        "n_features_in": len(features),
        "n_features_kept": len(kept_names),
        "dropped": {r: n for r, n in counts.iter_rows() if r},
    }
    recorder.write(
        out,
        inputs=[matrix_path, Path(eda_dir) / "columns.csv"],
        outputs=[(out, {"n_rows": out_df.height, "n_cols": len(kept_names)}), (report, {})],
        extensions=summary,
    )
    return summary
