from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import polars as pl
import pytest

from kpnf.cli import EXIT_DATA, EXIT_OK, main
from kpnf.concat import concat_blocks
from kpnf.io import KpnfError
from kpnf.select import SelectionSettings, select_block


def _eda(df: pl.DataFrame, folder: Path) -> Path:
    """Minimal stand-in for `ruddy inspect univariate` output (columns.csv + numeric_statistics.csv)."""
    folder.mkdir()
    rows, stats = [], []
    for c in df.columns:
        col = df.get_column(c)
        if c == "id":
            continue
        rows.append({"column": c, "missing_fraction": col.null_count() / df.height,
                     "is_constant": col.drop_nulls().n_unique() <= 1})
        stats.append({"column": c, "variance": col.var()})
    pl.DataFrame(rows).write_csv(folder / "columns.csv")
    pl.DataFrame(stats).write_csv(folder / "numeric_statistics.csv")
    return folder


@pytest.fixture
def block(tmp_path: Path) -> tuple[Path, Path]:
    rng = np.random.default_rng(0)
    n = 40
    a = rng.normal(size=n)
    df = pl.DataFrame({
        "id": [f"s{i}" for i in range(n)],
        "a": a,
        "a_copy": a * 3 + 1,                      # redundant with a (|rho| = 1)
        "b": rng.normal(size=n),
        "const": np.ones(n),
        "near": np.r_[np.zeros(n - 1), 1.0],  # 39 zeros and a single 1: mode fraction 0.975
        "holes": [None if i % 4 == 0 else float(i) for i in range(n)],
    })
    path = tmp_path / "m.parquet"
    df.write_parquet(path)
    return path, _eda(df, tmp_path / "eda")


def test_select_reasons(block, tmp_path):
    matrix, eda = block
    out, rep = tmp_path / "sel.parquet", tmp_path / "sel.csv"
    summary = select_block(matrix, eda, out, rep, settings=SelectionSettings(near_constant=0.95))
    report = {r["feature"]: r for r in pl.read_csv(rep).iter_rows(named=True)}
    assert report["holes"]["reason"] == "missing"
    assert report["const"]["reason"] == "constant"
    assert report["near"]["reason"] == "near_constant"
    # a_copy has 9x the variance of a, so it is visited first and a becomes the redundant one.
    assert report["a"]["reason"] == "redundant" and report["a"]["redundant_with"] == "a_copy"
    assert pl.read_parquet(out).columns == ["id", "a_copy", "b"]
    assert summary["n_features_kept"] == 2
    side = json.loads((tmp_path / "sel.parquet.provenance.json").read_text())
    assert side["schema_version"] == "provenance/1" and side["command"] == "select"


def test_select_rejects_foreign_eda(block, tmp_path):
    matrix, _ = block
    other = _eda(pl.DataFrame({"id": ["x"], "zzz": [1.0]}), tmp_path / "eda2")
    with pytest.raises(KpnfError, match="does not describe"):
        select_block(matrix, other, tmp_path / "o.parquet", tmp_path / "o.csv", settings=SelectionSettings())


def _write(path: Path, ids, **cols) -> Path:
    pl.DataFrame({"id": ids, **cols}).write_csv(path)
    return path


def test_concat_prefix_order_and_block_scaling(tmp_path):
    x = _write(tmp_path / "x.csv", ["a", "b", "c"], p_0=[1.0, 2.0, 3.0], p_1=[0.0, 1.0, 5.0])
    y = _write(tmp_path / "y.csv", ["c", "a", "b"], p_0=[9.0, 1.0, 4.0])  # same ids, other order, same column name
    out = tmp_path / "comp.parquet"
    summary = concat_blocks([("emb", x), ("desc", y)], out, scaling="block")
    df = pl.read_parquet(out)
    assert df.columns == ["id", "emb__p_0", "emb__p_1", "desc__p_0"]
    assert df["id"].to_list() == ["a", "b", "c"]
    assert df.filter(pl.col("id") == "c")["desc__p_0"][0] > 0  # aligned by id, not by position
    # block scaling: each block's columns sum to the same total variance (1)
    assert np.isclose(df.select("emb__p_0", "emb__p_1").to_numpy().var(axis=0, ddof=1).sum(), 1.0)
    assert np.isclose(df["desc__p_0"].var(), 1.0)
    assert summary["blocks"][1] == {"block": "desc", "n_features": 1, "first_column": 2, "last_column": 2}
    assert (tmp_path / "comp.blocks.json").is_file()


def test_concat_strict_vs_partial(tmp_path):
    x = _write(tmp_path / "x.csv", ["a", "b", "c"], f=[1.0, 2.0, 4.0])
    y = _write(tmp_path / "y.csv", ["a", "b", "d"], g=[1.0, 3.0, 2.0])
    with pytest.raises(KpnfError, match="do not share the same ids"):
        concat_blocks([("x", x), ("y", y)], tmp_path / "s.parquet")
    summary = concat_blocks([("x", x), ("y", y)], tmp_path / "p.parquet", alignment="partial")
    assert summary["n_rows"] == 2 and summary["dropped_ids"] == {"x": ["c"], "y": ["d"]}


def test_concat_refuses_missing_values(tmp_path):
    x = _write(tmp_path / "x.csv", ["a", "b"], f=[1.0, None])
    y = _write(tmp_path / "y.csv", ["a", "b"], g=[1.0, 3.0])
    with pytest.raises(KpnfError, match="does not impute"):
        concat_blocks([("x", x), ("y", y)], tmp_path / "o.parquet")


def test_concat_drops_ruddy_row_index(tmp_path):
    scores = _write(tmp_path / "pca_scores.csv", ["a", "b", "c"], source_row_index=[0, 1, 2], PC1=[1.0, 2.0, 0.0])
    y = _write(tmp_path / "y.csv", ["a", "b", "c"], g=[1.0, 3.0, 2.0])
    concat_blocks([("pca", scores), ("y", y)], tmp_path / "o.parquet")
    assert pl.read_parquet(tmp_path / "o.parquet").columns == ["id", "pca__PC1", "y__g"]


def test_cli_exit_codes_and_stage_manifest(tmp_path, capsys):
    m = tmp_path / "manifest.csv"
    m.write_text("id,path,chain\nx,/data/a/1abc.pdb,A\ny,rel/2xyz.pdb,B\n")
    assert main(["stage-manifest", str(m), "--prefix", "s/", "--out", str(tmp_path / "local.csv")]) == EXIT_OK
    local = pl.read_csv(tmp_path / "local.csv")
    assert local["path"].to_list() == ["s/1abc.pdb", "s/2xyz.pdb"] and local["chain"].to_list() == ["A", "B"]
    m.write_text("id,path\nx,/a/1abc.pdb\ny,/b/1abc.pdb\n")
    assert main(["stage-manifest", str(m), "--out", str(tmp_path / "l2.csv")]) == EXIT_DATA
    assert main(["concat", "--block", "bad", "--out", "x.parquet"]) == EXIT_DATA
    assert main(["select"]) == 2
