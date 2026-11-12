"""Table I/O shared by the kpnf commands."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import polars as pl


class KpnfError(Exception):
    """Data or configuration problem reported to the user without a traceback (exit 3)."""


def read_table(path: str | Path) -> pl.DataFrame:
    path = Path(path)
    suffix = path.suffix.lower()
    if suffix == ".parquet":
        return pl.read_parquet(path)
    if suffix in {".csv", ".tsv", ".txt"}:
        return pl.read_csv(path, separator="\t" if suffix != ".csv" else ",", infer_schema_length=10000)
    raise KpnfError(f"{path}: unsupported table format {suffix!r} (expected .csv, .tsv or .parquet)")


def write_table(df: pl.DataFrame, path: str | Path) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() == ".parquet":
        df.write_parquet(path)
    elif path.suffix.lower() == ".csv":
        df.write_csv(path)
    else:
        raise KpnfError(f"{path}: output must be .csv or .parquet")
    return path


def split_matrix(df: pl.DataFrame, id_column: str, *, source: str) -> tuple[list[str], list[str], np.ndarray]:
    """Return ids, feature names and a float matrix. Ids must exist, be non-empty and unique."""
    if id_column not in df.columns:
        raise KpnfError(f"{source}: id column {id_column!r} not found (columns: {', '.join(df.columns[:8])}...)")
    ids = df.get_column(id_column).cast(pl.String)
    if ids.null_count() or (ids.str.len_chars() == 0).any():
        raise KpnfError(f"{source}: id column {id_column!r} has empty values")
    dup = ids.filter(ids.is_duplicated()).unique().to_list()
    if dup:
        raise KpnfError(f"{source}: duplicated ids: {', '.join(map(str, dup[:10]))}")
    features = [c for c in df.columns if c != id_column]
    non_numeric = [c for c in features if not df.schema[c].is_numeric()]
    if non_numeric:
        raise KpnfError(f"{source}: non-numeric feature columns: {', '.join(non_numeric[:10])}")
    matrix = df.select(features).cast(pl.Float64).to_numpy() if features else np.empty((df.height, 0))
    return ids.to_list(), features, matrix
