"""Glue operations for the kaleidoprot-nf pipeline."""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("kpnf")
except PackageNotFoundError:  # pragma: no cover - running from a source tree
    __version__ = "0.0.0"
