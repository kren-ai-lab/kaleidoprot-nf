"""Rewrite an Eris manifest so that structure paths point to files staged in the work directory."""

from __future__ import annotations

from pathlib import Path

import polars as pl

from kpnf.io import KpnfError, read_table, write_table


def stage_manifest(
    manifest: str | Path,
    out: str | Path,
    *,
    path_column: str = "path",
    prefix: str = "",
    input_table: str | Path | None = None,
) -> int:
    df = pl.read_csv(manifest, infer_schema_length=10000)
    if input_table is not None:
        # Strict alignment: the manifest must cover exactly the ids of the input table.
        ids = set(df.get_column("id").cast(pl.String))
        wanted = set(read_table(input_table).get_column("id").cast(pl.String))
        for what, diff in (
            (f"ids of {input_table} have no structure", wanted - ids),
            (f"structures have no row in {input_table}", ids - wanted),
        ):
            if diff:
                raise KpnfError(
                    f"{manifest}: {len(diff)} {what}: {', '.join(sorted(diff)[:5])}; "
                    "fix the manifest or use alignment: partial"
                )
    if path_column not in df.columns:
        raise KpnfError(f"{manifest}: column {path_column!r} not found")
    names = df.get_column(path_column).map_elements(lambda p: Path(p).name, return_dtype=pl.String)
    dup = names.filter(names.is_duplicated()).unique().to_list()
    if dup:
        raise KpnfError(
            f"{manifest}: several structures share the file name {', '.join(dup[:5])}; rename them"
        )
    write_table(df.with_columns((prefix + names).alias(path_column)), out)
    return df.height
