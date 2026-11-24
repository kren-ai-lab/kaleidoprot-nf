# Changelog

## Unreleased

- Prototype pipeline: REPRESENT (Sylphy encode/embed, Roxy, Eris with validate-config preflight),
  CHARACTERIZE (Ruddy EDA, PCA, figures, pairwise representation comparison), COMPOSE (raw,
  PCA-reduced or selected blocks, concatenation, final PCA) and an aggregated report.
- `kpnf` package: `stage-manifest`, `select`, `concat`, `plot`, `report`, with `provenance/1` sidecars.
- Test profile on 16 public PDB entries (`examples/test`).
- `docker` and `apptainer` profiles: each process runs the released image of its tool from `ghcr.io/kren-ai-lab`. `stage-manifest` runs in its own task (`KPNF_STAGE_MANIFEST`), so Eris needs only its own image.
- kpnf image on `ghcr.io/kren-ai-lab/kpnf`: `<version>` and `latest` on release tags, `main` on pushes to main.
- The local profile installs the released libraries from PyPI (Sylphy 1.2.1, Roxy 0.4.0, Eris 0.2.0, Ruddy 0.2.1).
