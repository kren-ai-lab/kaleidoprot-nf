"""Aggregate the pipeline outputs into ``report.md`` and ``summary.json``.

Expected layout of ``results_dir`` (the pipeline stages everything under these names):

- ``representations/<rep>.<ext>.provenance.json`` sidecars of each representation matrix
- ``projections/pca_<id>/`` Ruddy PCA directories (``pca_variance.csv``)
- ``comparisons/cmp_<a>__<b>/`` ``ruddy analyze representation`` directories
- ``selection/<comp>__<rep>.selection.csv`` selection reports
- ``compositions/<comp>.blocks.json`` block maps written by ``kpnf concat``
- ``figures/<id>.png``
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

import polars as pl

from kpnf.provenance import Recorder


def _first(csv: Path, column: str, where: tuple[str, str] | None = None) -> Any:
    if not csv.is_file():
        return None
    df = pl.read_csv(csv)
    if "status" in df.columns:
        df = df.filter(pl.col("status") == "ok")
    if where is not None and where[0] in df.columns:
        df = df.filter(pl.col(where[0]).cast(pl.String) == where[1])
    if df.is_empty() or column not in df.columns:
        return None
    return df.get_column(column)[0]


def _fmt(value: Any, digits: int = 3) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


def _representations(root: Path) -> list[dict]:
    rows = []
    for sidecar in sorted((root / "representations").glob("*.provenance.json")):
        doc = json.loads(sidecar.read_text(encoding="utf-8"))
        out = (doc.get("outputs") or [{}])[0]
        name = sidecar.name.split(".")[0]
        rows.append(
            {
                "name": name,
                "tool": f"{doc['tool']['name']} {doc['tool'].get('version') or ''}".strip(),
                "command": doc.get("command"),
                "n_rows": out.get("n_rows"),
                "n_cols": out.get("n_cols"),
                "sha256": (out.get("sha256") or "")[:12],
            }
        )
    return rows


def _projections(root: Path) -> list[dict]:
    rows = []
    for d in sorted((root / "projections").glob("pca_*")):
        var = d / "pca_variance.csv"
        if not var.is_file():
            continue
        df = pl.read_csv(var)
        ratios = df.get_column("explained_variance_ratio").to_list()
        rows.append(
            {
                "id": d.name.removeprefix("pca_"),
                "n_components": len(ratios),
                "pc1": ratios[0] if ratios else None,
                "pc2": ratios[1] if len(ratios) > 1 else None,
                "cumulative": df.get_column("cumulative_explained_variance_ratio").to_list()[-1]
                if ratios
                else None,
            }
        )
    return rows


def _comparisons(root: Path) -> list[dict]:
    rows = []
    for d in sorted((root / "comparisons").glob("cmp_*")):
        a, _, b = d.name.removeprefix("cmp_").partition("__")
        alignment = {}
        if (d / "representation_alignment.json").is_file():
            alignment = json.loads((d / "representation_alignment.json").read_text(encoding="utf-8"))
        rows.append(
            {
                "x": a,
                "y": b,
                "n": alignment.get("covered_count"),
                "cka_linear": _first(d / "cka.csv", "cka", ("kernel", "linear")),
                "cca_1": _first(d / "cca_correlations.csv", "canonical_correlation"),
                "mantel_r": _first(d / "mantel.csv", "correlation"),
                "mantel_p": _first(d / "mantel.csv", "p_value"),
                "distance_rho": _first(d / "distance_similarity.csv", "coefficient"),
                "procrustes": _first(d / "procrustes.csv", "similarity"),
            }
        )
    return rows


def _selections(root: Path) -> list[dict]:
    rows = []
    for csv in sorted((root / "selection").glob("*.selection.csv")):
        df = pl.read_csv(csv)
        comp, _, rep = csv.name.removesuffix(".selection.csv").partition("__")
        dropped = df.filter(pl.col("status") == "dropped").group_by("reason").len().sort("reason")
        rows.append(
            {
                "composition": comp,
                "block": rep,
                "n_in": df.height,
                "n_kept": df.filter(pl.col("status") == "kept").height,
                "dropped": ", ".join(f"{r}: {n}" for r, n in dropped.iter_rows()) or "none",
            }
        )
    return rows


def _compositions(root: Path) -> list[dict]:
    rows = []
    for js in sorted((root / "compositions").glob("*.blocks.json")):
        doc = json.loads(js.read_text(encoding="utf-8"))
        rows.append(
            {
                "name": js.name.removesuffix(".blocks.json"),
                "n_rows": doc["n_rows"],
                "n_cols": doc["n_cols"],
                "blocks": " + ".join(f"{b['block']} ({b['n_features']})" for b in doc["blocks"]),
                "scaling": doc["scaling"],
                "alignment": doc["alignment"],
                "dropped_ids": sum(len(v) for v in doc["dropped_ids"].values()),
            }
        )
    return rows


def _table(rows: list[dict], columns: list[tuple[str, str]]) -> str:
    if not rows:
        return "_none_\n"
    head = "| " + " | ".join(t for _, t in columns) + " |\n|" + "---|" * len(columns) + "\n"
    body = "".join("| " + " | ".join(_fmt(r.get(k)) for k, _ in columns) + " |\n" for r in rows)
    return head + body


def build_report(
    results_dir: str | Path, out_dir: str | Path, *, title: str = "kaleidoprot-nf report"
) -> dict:
    root, out_dir = Path(results_dir), Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    recorder = Recorder("report", {"title": title})
    summary = {
        "representations": _representations(root),
        "projections": _projections(root),
        "comparisons": _comparisons(root),
        "selection": _selections(root),
        "compositions": _compositions(root),
        "figures": sorted(p.name for p in (root / "figures").glob("*.png")),
    }
    md = [f"# {title}\n"]
    md.append("\n## Representations\n\n")
    md.append(
        _table(
            summary["representations"],
            [
                ("name", "Name"),
                ("tool", "Tool"),
                ("command", "Command"),
                ("n_rows", "Rows"),
                ("n_cols", "Features"),
                ("sha256", "sha256"),
            ],
        )
    )
    md.append("\n## Feature selection\n\n")
    md.append(
        _table(
            summary["selection"],
            [
                ("composition", "Composition"),
                ("block", "Block"),
                ("n_in", "In"),
                ("n_kept", "Kept"),
                ("dropped", "Dropped (reason: n)"),
            ],
        )
    )
    md.append("\n## Compositions\n\n")
    md.append(
        _table(
            summary["compositions"],
            [
                ("name", "Name"),
                ("blocks", "Blocks (features)"),
                ("n_rows", "Rows"),
                ("n_cols", "Columns"),
                ("scaling", "Scaling"),
                ("alignment", "Alignment"),
                ("dropped_ids", "Ids dropped"),
            ],
        )
    )
    md.append("\n## Projections (PCA)\n\n")
    md.append(
        _table(
            summary["projections"],
            [
                ("id", "Id"),
                ("n_components", "Components"),
                ("pc1", "PC1"),
                ("pc2", "PC2"),
                ("cumulative", "Cumulative"),
            ],
        )
    )
    md.append("\n## Representation comparisons\n\n")
    md.append(
        _table(
            summary["comparisons"],
            [
                ("x", "X"),
                ("y", "Y"),
                ("n", "n"),
                ("cka_linear", "CKA (linear)"),
                ("cca_1", "CCA r1"),
                ("mantel_r", "Mantel r"),
                ("mantel_p", "Mantel p"),
                ("distance_rho", "Distance rho"),
                ("procrustes", "Procrustes"),
            ],
        )
    )
    md.append("\n## Figures\n\n")
    md.extend(
        f"### {name.removesuffix('.png')}\n\n![{name}](figures/{name})\n\n" for name in summary["figures"]
    )
    # Copy the figures next to the report so the directory is self-contained.
    (out_dir / "figures").mkdir(exist_ok=True)
    for name in summary["figures"]:
        shutil.copyfile(root / "figures" / name, out_dir / "figures" / name)
    report_md = out_dir / "report.md"
    report_md.write_text("".join(md), encoding="utf-8")
    summary_json = out_dir / "summary.json"
    summary_json.write_text(json.dumps(summary, indent=2, default=str) + "\n", encoding="utf-8")
    recorder.write(
        report_md,
        inputs=[],
        outputs=[(report_md, {}), (summary_json, {})],
        extensions={k: len(v) for k, v in summary.items()},
    )
    return summary
