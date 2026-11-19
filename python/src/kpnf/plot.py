"""Scatter plot of a Ruddy PCA output directory, coloured by a label column."""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import polars as pl  # noqa: E402

from kpnf.io import KpnfError, read_table  # noqa: E402
from kpnf.provenance import Recorder  # noqa: E402

MAX_LEGEND_LEVELS = 20


def plot_projection(
    pca_dir: str | Path,
    out: str | Path,
    *,
    title: str,
    labels: str | Path | None = None,
    label_column: str | None = None,
    id_column: str = "id",
) -> dict:
    pca_dir = Path(pca_dir)
    scores_csv = pca_dir / "pca_scores.csv"
    if not scores_csv.is_file():
        raise KpnfError(f"{pca_dir}: pca_scores.csv not found; expected the output of `ruddy project pca`")
    recorder = Recorder("plot", {"title": title, "label_column": label_column, "id_column": id_column})
    scores = pl.read_csv(scores_csv, schema_overrides={"id": pl.String}).rename(
        {"id": id_column} if id_column != "id" else {}
    )
    if not {"PC1", "PC2"} <= set(scores.columns):
        raise KpnfError(f"{scores_csv}: a 2D plot needs PC1 and PC2")
    inputs = [scores_csv]

    axis = {"PC1": "PC1", "PC2": "PC2"}
    variance_csv = pca_dir / "pca_variance.csv"
    if variance_csv.is_file():
        var = pl.read_csv(variance_csv)
        for row in var.iter_rows(named=True):
            if row["component"] in axis:
                axis[row["component"]] = f"{row['component']} ({100 * row['explained_variance_ratio']:.1f}%)"

    fig, ax = plt.subplots(figsize=(5.5, 4.5), dpi=150)
    n_unlabelled = 0
    if labels is not None and label_column:
        meta = read_table(labels)
        if label_column not in meta.columns:
            raise KpnfError(f"{labels}: label column {label_column!r} not found")
        meta = meta.select(pl.col(id_column).cast(pl.String), pl.col(label_column).cast(pl.String))
        merged = scores.join(meta, on=id_column, how="left")
        n_unlabelled = merged.get_column(label_column).null_count()
        merged = merged.with_columns(pl.col(label_column).fill_null("(no label)"))
        levels = sorted(merged.get_column(label_column).unique().to_list())
        for level in levels:
            sub = merged.filter(pl.col(label_column) == level)
            ax.scatter(sub["PC1"], sub["PC2"], s=14, alpha=0.8, label=level)
        if len(levels) <= MAX_LEGEND_LEVELS:
            ax.legend(title=label_column, fontsize=7, title_fontsize=8, frameon=False, loc="best")
        inputs.append(Path(labels))
    else:
        ax.scatter(scores["PC1"], scores["PC2"], s=14, alpha=0.8)
    ax.set_xlabel(axis["PC1"])
    ax.set_ylabel(axis["PC2"])
    ax.set_title(title, fontsize=10)
    fig.tight_layout()
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out)
    plt.close(fig)
    summary = {"n_points": scores.height, "n_unlabelled": n_unlabelled}
    recorder.write(out, inputs=inputs, outputs=[(out, {})], extensions=summary)
    return summary
