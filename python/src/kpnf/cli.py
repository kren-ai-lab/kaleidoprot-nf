"""``kpnf`` command line. Exit codes follow the ecosystem contract: 0 ok, 2 usage, 3 data/runtime, 4 internal."""

from __future__ import annotations

import argparse
import json
import sys
import traceback

from kpnf import __version__
from kpnf.io import KpnfError

EXIT_OK, EXIT_USAGE, EXIT_DATA, EXIT_INTERNAL = 0, 2, 3, 4


def _parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="kpnf", description=__doc__)
    p.add_argument("--version", action="version", version=f"kpnf {__version__}")
    sub = p.add_subparsers(dest="command", required=True)

    s = sub.add_parser("stage-manifest", help="Point an Eris manifest to staged structure basenames.")
    s.add_argument("manifest")
    s.add_argument("--out", required=True)
    s.add_argument("--path-column", default="path")
    s.add_argument("--prefix", default="", help="Prepended to every basename (e.g. the staging directory).")
    s.add_argument("--input", help="Table whose ids the manifest must match exactly (strict alignment).")

    s = sub.add_parser("select", help="Unsupervised feature filtering of one block from its Ruddy EDA.")
    s.add_argument("matrix")
    s.add_argument("--eda-dir", required=True, help="Output directory of `ruddy inspect univariate`.")
    s.add_argument("--out", required=True)
    s.add_argument("--report", required=True)
    s.add_argument("--id-column", default="id")
    s.add_argument("--max-missing", type=float, default=0.0)
    s.add_argument("--near-constant", type=float, default=0.99)
    s.add_argument("--abs-rho", type=float, default=0.90)
    s.add_argument("--method", choices=["spearman", "pearson"], default="spearman")
    s.add_argument("--max-features", type=int, default=None)

    s = sub.add_parser("concat", help="Align blocks by id, prefix columns and scale.")
    s.add_argument(
        "--block",
        action="append",
        required=True,
        metavar="NAME=PATH",
        help="Repeatable; order is kept in the output.",
    )
    s.add_argument("--out", required=True)
    s.add_argument("--id-column", default="id")
    s.add_argument("--scaling", choices=["none", "standard", "block"], default="standard")
    s.add_argument("--alignment", choices=["strict", "partial"], default="strict")

    s = sub.add_parser("plot", help="Scatter plot of a Ruddy PCA directory.")
    s.add_argument("pca_dir")
    s.add_argument("--out", required=True)
    s.add_argument("--title", required=True)
    s.add_argument("--labels", default=None, help="Table with the id column and the label column.")
    s.add_argument("--label-column", default=None)
    s.add_argument("--id-column", default="id")

    s = sub.add_parser("report", help="Aggregate pipeline outputs into report.md and summary.json.")
    s.add_argument("results_dir")
    s.add_argument("--out-dir", required=True)
    s.add_argument("--title", default="kaleidoprot-nf report")
    return p


def _run(args: argparse.Namespace) -> dict | int:
    if args.command == "stage-manifest":
        from kpnf.manifest import stage_manifest

        return {
            "rows": stage_manifest(
                args.manifest,
                args.out,
                path_column=args.path_column,
                prefix=args.prefix,
                input_table=args.input,
            )
        }
    if args.command == "select":
        from kpnf.select import SelectionSettings, select_block

        settings = SelectionSettings(
            args.max_missing, args.near_constant, args.abs_rho, args.method, args.max_features
        )
        return select_block(
            args.matrix, args.eda_dir, args.out, args.report, id_column=args.id_column, settings=settings
        )
    if args.command == "concat":
        from kpnf.concat import concat_blocks

        blocks = []
        for spec in args.block:
            name, sep, path = spec.partition("=")
            if not sep or not name or not path:
                raise KpnfError(f"--block expects NAME=PATH, got {spec!r}")
            blocks.append((name, path))
        return concat_blocks(
            blocks, args.out, id_column=args.id_column, scaling=args.scaling, alignment=args.alignment
        )
    if args.command == "plot":
        from kpnf.plot import plot_projection

        return plot_projection(
            args.pca_dir,
            args.out,
            title=args.title,
            labels=args.labels,
            label_column=args.label_column,
            id_column=args.id_column,
        )
    if args.command == "report":
        from kpnf.report import build_report

        s = build_report(args.results_dir, args.out_dir, title=args.title)
        return {k: len(v) for k, v in s.items()}
    raise AssertionError(args.command)


def main(argv: list[str] | None = None) -> int:
    try:
        args = _parser().parse_args(argv)
    except SystemExit as exc:  # argparse: 0 for --help/--version, 2 for usage errors
        return int(exc.code or 0)
    try:
        result = _run(args)
    except KpnfError as exc:
        print(f"kpnf {args.command}: error: {exc}", file=sys.stderr)
        return EXIT_DATA
    except Exception:  # noqa: BLE001
        traceback.print_exc()
        return EXIT_INTERNAL
    print(json.dumps(result, default=str))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
