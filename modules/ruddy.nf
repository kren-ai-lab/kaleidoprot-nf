// Ruddy: EDA, projections and comparison of representation spaces.
// Nothing is imputed. PCA excludes features with non-finite values (recorded in its provenance) rather than rows,
// so every id stays; the other decisions taken from Ruddy's outputs live in kpnf.
// An analysis the data does not allow (exit 3) is recorded as <name>.failed for the report instead of stopping the run.

process RUDDY_EDA {
    tag "${meta.name}"
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/ruddy:0.2.2'
    publishDir "${params.outdir}/eda", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(matrix)

    output:
    tuple val(meta.name), path("eda_${meta.name}"), optional: true, emit: eda
    path "eda_${meta.name}.provenance.json", optional: true, emit: provenance
    path "eda_${meta.name}.failed", optional: true, emit: failed

    script:
    """
    soft-fail eda_${meta.name} ruddy -q inspect univariate ${matrix} \\
        --id-column id \\
        --max-pairwise-columns ${params.eda_max_columns} \\
        --output-dir eda_${meta.name}
    """

    stub:
    """
    mkdir -p eda_${meta.name}
    touch eda_${meta.name}.provenance.json
    """
}

process RUDDY_PCA {
    tag "${meta.id}"
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/ruddy:0.2.2'
    publishDir "${params.outdir}/projections", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(matrix)

    output:
    tuple val(meta), path("pca_${meta.id}"), optional: true, emit: pca
    path "pca_${meta.id}.provenance.json", optional: true, emit: provenance
    path "pca_${meta.id}.failed", optional: true, emit: failed

    script:
    """
    soft-fail pca_${meta.id} ruddy -q project pca ${matrix} \\
        --id-column id \\
        --n-components ${meta.n_components} \\
        --scaling ${meta.scaling} \\
        --non-finite exclude_features \\
        --random-state ${params.seed} \\
        --output-dir pca_${meta.id}
    """

    stub:
    """
    mkdir -p pca_${meta.id}
    touch pca_${meta.id}.provenance.json
    """
}

process RUDDY_COMPARE {
    tag "${x_name} vs ${y_name}"
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/ruddy:0.2.2'
    publishDir "${params.outdir}/comparisons", mode: params.publish_dir_mode

    input:
    tuple val(x_name), path(x_matrix, stageAs: 'x/*'), val(y_name), path(y_matrix, stageAs: 'y/*')

    output:
    path "cmp_${x_name}__${y_name}", optional: true, emit: comparison
    path "cmp_${x_name}__${y_name}.provenance.json", optional: true, emit: provenance
    path "cmp_${x_name}__${y_name}.failed", optional: true, emit: failed

    script:
    // PCA scores also carry source_row_index, so the features are named explicitly.
    def features = (1..params.comparison_components).collect { i -> "--x-feature-column PC${i} --y-feature-column PC${i}" }.join(' ')
    """
    soft-fail cmp_${x_name}__${y_name} ruddy -q analyze representation ${x_matrix} ${y_matrix} \\
        --x-id-column id --y-id-column id \\
        ${features} \\
        --representation-alignment ${params.alignment} \\
        --mantel-permutations ${params.mantel_permutations} \\
        --random-state ${params.seed} \\
        --output-dir cmp_${x_name}__${y_name}
    """

    stub:
    """
    mkdir -p cmp_${x_name}__${y_name}
    touch cmp_${x_name}__${y_name}.provenance.json
    """
}
