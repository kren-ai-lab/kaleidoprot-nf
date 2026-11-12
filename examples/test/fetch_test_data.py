#!/usr/bin/env python
"""Download a small labelled set of PDB entries and build the pipeline inputs.

Writes, under OUT_DIR:
  structures/<ID>.pdb   one file per entry (RCSB)
  sequences.csv         id,sequence,family   (sequence read from the chosen chain of the structure)
  manifest.csv          id,path,chain        (Eris manifest, paths relative to the manifest)

Only for smoke tests: 16 X-ray entries from four families, so PCA plots should separate them.
Needs biotite (installed with Eris).

    python examples/test/fetch_test_data.py examples/test/data
"""

from __future__ import annotations

import csv
import sys
import urllib.request
from pathlib import Path

import biotite.structure as struc
import biotite.structure.io.pdb as pdb
from biotite.sequence import ProteinSequence

ENTRIES = {
    "lysozyme": ["1HEL", "1LZ1", "2LZM", "1DPX"],
    "globin": ["1MBN", "1A6M", "2HHB", "1HHO"],
    "kunitz": ["5PTI", "4PTI", "1BPI", "6PTI"],
    "ubiquitin": ["1UBQ", "1UBI", "1AAR", "1D3Z"],
}


def first_protein_chain(path: Path) -> tuple[str, str]:
    atoms = pdb.PDBFile.read(path).get_structure(model=1)
    atoms = atoms[struc.filter_amino_acids(atoms) & ~atoms.hetero]
    chain = atoms.chain_id[0]
    atoms = atoms[atoms.chain_id == chain]
    to_one = ProteinSequence.convert_letter_3to1
    seq = "".join(to_one(r) if r in ProteinSequence._dict_3to1 else "X" for r in struc.get_residues(atoms)[1])
    return chain, seq


def main(out_dir: str) -> int:
    out = Path(out_dir)
    (out / "structures").mkdir(parents=True, exist_ok=True)
    seq_rows, manifest_rows = [], []
    for family, ids in ENTRIES.items():
        for pdb_id in ids:
            target = out / "structures" / f"{pdb_id}.pdb"
            if not target.is_file():
                url = f"https://files.rcsb.org/download/{pdb_id}.pdb"
                try:
                    urllib.request.urlretrieve(url, target)
                except OSError as exc:
                    print(f"skip {pdb_id}: {exc}", file=sys.stderr)
                    continue
            chain, seq = first_protein_chain(target)
            seq_rows.append({"id": pdb_id, "sequence": seq, "family": family})
            manifest_rows.append({"id": pdb_id, "path": f"structures/{pdb_id}.pdb", "chain": chain})
            print(f"{pdb_id} {family} chain {chain} length {len(seq)}")
    for name, rows in (("sequences.csv", seq_rows), ("manifest.csv", manifest_rows)):
        with open(out / name, "w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    print(f"{len(seq_rows)} entries written to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "examples/test/data"))
