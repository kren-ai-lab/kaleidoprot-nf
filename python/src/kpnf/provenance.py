"""Write ``provenance/1`` sidecars with the same layout as Sylphy, Roxy, Eris and Ruddy."""

from __future__ import annotations

import hashlib
import json
import platform
from collections.abc import Iterable, Mapping
from datetime import UTC, datetime
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "provenance/1"


def _now() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256(path: str | Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _hash_entry(path: Path) -> dict[str, Any]:
    if path.is_dir():
        files = sorted(p for p in path.rglob("*") if p.is_file())
        combined = hashlib.sha256()
        for p in files:
            combined.update(str(p.relative_to(path)).encode())
            combined.update(sha256(p).encode())
        return {"path": str(path.resolve()), "sha256": combined.hexdigest(), "n_files": len(files)}
    return {"path": str(path.resolve()), "sha256": sha256(path)}


def _version(pkg: str) -> str | None:
    try:
        return version(pkg)
    except PackageNotFoundError:
        return None


class Recorder:
    """Collects the run context; ``write`` produces ``<output>.provenance.json``."""

    def __init__(self, command: str, parameters: Mapping[str, Any]) -> None:
        self.command = command
        self.parameters = dict(parameters)
        self.created_at = _now()

    def write(
        self,
        sidecar_for: str | Path,
        *,
        inputs: Iterable[str | Path],
        outputs: Iterable[tuple[str | Path, Mapping[str, Any]]],
        extensions: Mapping[str, Any] | None = None,
    ) -> Path:
        params_json = json.dumps(self.parameters, sort_keys=True, default=str)
        doc = {
            "schema_version": SCHEMA_VERSION,
            "tool": {"name": "kpnf", "version": _version("kpnf")},
            "command": self.command,
            "created_at": self.created_at,
            "finished_at": _now(),
            "parameters": json.loads(params_json),
            "config_fingerprint": "sha256:" + hashlib.sha256(params_json.encode()).hexdigest(),
            "inputs": [_hash_entry(Path(p)) for p in inputs],
            "outputs": [{**_hash_entry(Path(p)), **dict(extra)} for p, extra in outputs],
            "environment": {
                "python": platform.python_version(),
                "platform": platform.platform(),
                "packages": {
                    k: v for k in ("kpnf", "numpy", "polars", "matplotlib") if (v := _version(k)) is not None
                },
            },
            "extensions": dict(extensions or {}),
        }
        target = Path(sidecar_for)
        sidecar = target.with_name(target.name + ".provenance.json")
        sidecar.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        return sidecar
