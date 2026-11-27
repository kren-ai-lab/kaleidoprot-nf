# Changelog

## Unreleased

- Prototype pipeline: VALIDATE (`validate-config` of every config before anything runs), REPRESENT (Sylphy encode/embed, Roxy, Eris),
  CHARACTERIZE (Ruddy EDA, PCA, figures, pairwise representation comparison), COMPOSE (raw,
  PCA-reduced or selected blocks, concatenation, final PCA) and an aggregated report.
- `kpnf` package: `stage-manifest`, `select`, `concat`, `plot`, `report`, with `provenance/1` sidecars.
- Test profile on 16 public PDB entries (`examples/test`).
- CI lints the pipeline and runs the test profile with stub tasks (`-stub`).
- Representation pairs are compared on their standardized PCA scores (`comparison_components`, default 5) instead of the raw matrices, so Procrustes runs and large-magnitude columns no longer dominate CKA and Mantel.
- A representation's `config` can hold the tool's options inline in `params.yaml`, or the path to its `--config` file. The test example uses inline configs.
- `docker` and `apptainer` profiles: each process runs the released image of its tool from `ghcr.io/kren-ai-lab`. `stage-manifest` runs in its own task (`KPNF_STAGE_MANIFEST`), so Eris needs only its own image.
- kpnf image on `ghcr.io/kren-ai-lab/kpnf`: `<version>` and `latest` on release tags, `main` on pushes to main.
- A representation or analysis that the data does not allow (the tool exits 3) no longer stops the run: it is skipped, with its error under "Failed steps" in the report, and the steps that need it are not run. Other errors still stop the run.
- Unknown parameters (e.g. a misspelled `seq_column`) are rejected before any task runs.
- With `alignment: strict`, the structure manifest must have exactly the ids of `input`.
- `docker` profile: HOME points to the task directory, so tools can write their caches and logs when run as the host user.
- `cache_dir`: persistent cache for the models `sylphy embed` downloads, mounted in the docker and apptainer profiles. Without it, each task downloads its own copy.
- The local profile installs the released libraries from PyPI (Sylphy 1.2.1, Roxy 0.4.0, Eris 0.2.0, Ruddy 0.2.1).
