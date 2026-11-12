# Design notes

Scope of this prototype, the decisions behind it, and what is still open. It follows the direction
proposed in reply to the KaleidoProt specification v3.1: a plain Nextflow pipeline over the four
libraries, each tool driven by its own homologated `--config`, plus a small Python package for the
operations that belong to no library.

## What is covered

| Specification item | Here |
|---|---|
| W1–W3, W5: generate several representations of one dataset | `REPRESENT`: fan-out over `representations`; a closed list, a failed representation stops the run instead of being skipped |
| W4: characterize and compare representation spaces | `CHARACTERIZE`: Ruddy EDA + PCA + figure per representation; `ruddy analyze representation` per pair |
| W6: compose representations | `COMPOSE`: one level; each block raw, PCA-reduced (Ruddy) or filtered (`kpnf select`); `kpnf concat`; final Ruddy PCA + figure |
| Preflight | `checkParams` in `main.nf` (names, tools, references between entries) and `<tool> validate-config` for every config before any representation starts |
| Traceability | every output has a `provenance/1` sidecar; `kpnf` writes the same layout as the libraries; composed columns carry the block prefix and `<comp>.blocks.json` maps column ranges to blocks |

## Rules kept from the specification

- Rows are aligned by `id`, never by position. `strict` alignment fails when blocks do not cover
  the same ids; `partial` keeps the intersection and reports what was dropped.
- No zero-filling and no imputation. A block with missing values stops the composition with a
  message that points to `selection.max_missing`.
- Level conversions are explicit: Eris structure-level features are requested with
  `features_source`; reduction happens only when a block says `reduce: N`.
- Projections come from Ruddy only (Sylphy's reductions are not used).

## Decisions

- **Modules do not know tool options.** Paths go as flags; everything else lives in the
  representation's config file, which the tool itself validates. Adding a descriptor family or a
  model is a config change, not a pipeline change.
- **Eris runs as one task** (batch encode, pack, features). The structure-level table is what the
  rest of the pipeline consumes; native artifacts are published for reuse.
- **Selection is unsupervised and per block.** Criteria and defaults follow the unsupervised branch
  of `krenai_pipelines/pipeline_feature_selection` (missingness, constant, near-constant, direct
  greedy redundancy on |Spearman rho| > 0.90). Supervised selection stays in that pipeline.
  `max_missing` defaults to 0 because compositions refuse missing values.
- **Scaling `block`** standardizes every column and then divides by sqrt(n_columns of the block),
  so each block contributes the same total variance. Without it a 1,700-column descriptor block
  outweighs a 6-component embedding block.
- **One environment, tools on `PATH`.** Containers per tool are the next step for HPC runs.

## Not covered

- Nested compositions (a composition as a block of another) and arbitrary DAGs from configuration.
  They are not expressible in Nextflow without generating code; the Python API is the place for them.
- Residue-level embeddings: Sylphy returns pooled per-sequence embeddings only.
- Supervised selection, model training and benchmarking (other KrenAI pipelines).

## Findings from the first run (16 PDB entries)

1. **typer 0.28+ breaks `validate-config`** in Sylphy (valid values reported as invalid) and Eris
   (`'TyperOption' object has no attribute 'type'`). The libraries only bound `typer<1`; their
   lockfiles use 0.27.3. `envs/requirements.txt` pins `typer<0.28` until the libraries fix or bound it.
2. **CCA on raw matrices is uninformative when features ≥ samples**: the first canonical correlation
   is 1.0 for every pair. Compare reduced spaces, or have Ruddy warn when p ≥ n.
3. **CKA and Mantel on unscaled descriptor tables** are dominated by large-magnitude columns
   (length, number of nodes): Roxy composition vs Eris contact graph gives linear CKA 0.995 on the
   raw tables and 0.757 after standardizing every column; the largest-variance columns are
   `length`/`valid_residue_count` (Roxy) and `n_edges`/`n_nodes` (Eris). Comparisons should run on
   standardized matrices; Ruddy has no scaling option for CKA/Mantel (only CCA).
4. **The Eris `features` sidecar has no `n_rows`/`n_cols`** in its output entry (Sylphy and Roxy record them).
5. **Duplicate sequences limit PCA rank**: the test set has identical sequences (several BPTI and
   ubiquitin entries), so 16 rows give 8 non-zero components. Ruddy reports it clearly; `reduce`
   must stay below the rank.

## Next steps

- Run on a real dataset with a GPU model (`esm2_t33_650M`, `device: cuda`).
- Containers per tool and a Slurm profile tested on Ulem.
- Decide whether comparisons should run on standardized or reduced matrices (findings 2 and 3).
- `ecosystem-alignment-4`: option names (`--id-col` / `--id-column`, `-o` / `--out` /
  `--output-dir`), `-h` in Eris, Eris manifest paths relative to the manifest, sidecar counts in Eris.
