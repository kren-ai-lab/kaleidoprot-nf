nextflow.enable.types = true

// Ruddy: EDA, projections and comparison of representation spaces.
// Nothing is imputed. PCA excludes features with non-finite values (recorded in its provenance) rather than rows,
// so every id stays; the other decisions taken from Ruddy's outputs live in kpnf.
// An analysis the data does not allow (exit 3) is recorded as <name>.failed for the report instead of stopping the run.

process RUDDY_EDA {
    tag name
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/ruddy:0.2.2'

    input:
    record(name: String, matrix: Path)
    max_columns: Integer

    output:
    record(
        name: name,
        eda: file("eda_${name}", optional: true),
        provenance: file("eda_${name}.provenance.json", optional: true),
        failed: file("eda_${name}.failed", optional: true)
    )

    script:
    """
    soft-fail eda_${name} ruddy -q inspect univariate ${matrix} \\
        --id-column id \\
        --max-pairwise-columns ${max_columns} \\
        --output-dir eda_${name}
    """

    stub:
    """
    mkdir -p eda_${name}
    touch eda_${name}.provenance.json
    """
}

process RUDDY_PCA {
    tag id
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/ruddy:0.2.2'

    input:
    record(id: String, title: String, n_components: Integer, scaling: String, matrix: Path)
    seed: Integer

    output:
    record(
        id: id,
        title: title,
        pca: file("pca_${id}", optional: true),
        provenance: file("pca_${id}.provenance.json", optional: true),
        failed: file("pca_${id}.failed", optional: true)
    )

    script:
    """
    soft-fail pca_${id} ruddy -q project pca ${matrix} \\
        --id-column id \\
        --n-components ${n_components} \\
        --scaling ${scaling} \\
        --non-finite exclude_features \\
        --random-state ${seed} \\
        --output-dir pca_${id}
    """

    stub:
    """
    mkdir -p pca_${id}
    touch pca_${id}/pca_scores.csv
    touch pca_${id}.provenance.json
    """
}

process RUDDY_COMPARE {
    tag "${x} vs ${y}"
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/ruddy:0.2.2'

    input:
    record(x: String, x_scores: Path, y: String, y_scores: Path)
    components: Integer
    alignment: String
    permutations: Integer
    seed: Integer

    stage:
    stageAs x_scores, 'x/*'
    stageAs y_scores, 'y/*'

    output:
    record(
        x: x,
        y: y,
        comparison: file("cmp_${x}__${y}", optional: true),
        provenance: file("cmp_${x}__${y}.provenance.json", optional: true),
        failed: file("cmp_${x}__${y}.failed", optional: true)
    )

    script:
    // PCA scores also carry source_row_index, so the features are named explicitly.
    def features = (1..components).collect { i -> "--x-feature-column PC${i} --y-feature-column PC${i}" }.join(' ')
    """
    soft-fail cmp_${x}__${y} ruddy -q analyze representation ${x_scores} ${y_scores} \\
        --x-id-column id --y-id-column id \\
        ${features} \\
        --representation-alignment ${alignment} \\
        --mantel-permutations ${permutations} \\
        --random-state ${seed} \\
        --output-dir cmp_${x}__${y}
    """

    stub:
    """
    mkdir -p cmp_${x}__${y}
    touch cmp_${x}__${y}.provenance.json
    """
}
