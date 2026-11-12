# kpnf

Small helper package used by the `kaleidoprot-nf` pipeline. It holds the operations that do not
belong to any of the four libraries (Sylphy, Roxy, Eris, Ruddy):

| Command | What it does |
|---|---|
| `kpnf stage-manifest` | Rewrites an Eris manifest so structure paths point to staged basenames. |
| `kpnf select` | Unsupervised feature filtering of one block from its Ruddy EDA (missingness, constant, near-constant, correlation redundancy). |
| `kpnf concat` | Aligns blocks by id, prefixes columns with the block name and scales them. |
| `kpnf plot` | Scatter plot of a Ruddy PCA, coloured by a label column. |
| `kpnf report` | Aggregates the pipeline outputs into `report.md` and `summary.json`. |

Every file output gets a `<file>.provenance.json` sidecar with the same `provenance/1` layout the
four libraries write, so lineage can be rebuilt by matching output and input hashes.

Projections are not computed here: they come from `ruddy project pca`. Supervised feature
selection is out of scope (see `krenai_pipelines/pipeline_feature_selection`).

```bash
uv pip install -e python/
pytest python/tests
```
