// Ruddy: EDA, projections and comparison of representation spaces.
// Ruddy never drops or imputes; the decisions taken from its outputs live in kpnf.

process RUDDY_EDA {
    tag "${meta.name}"
    label 'process_medium'
    publishDir "${params.outdir}/eda", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(matrix)

    output:
    tuple val(meta.name), path("eda_${meta.name}"), emit: eda
    path "eda_${meta.name}.provenance.json", emit: provenance

    script:
    """
    ruddy -q inspect univariate ${matrix} \\
        --id-column id \\
        --max-pairwise-columns ${params.eda_max_columns} \\
        --output-dir eda_${meta.name}
    """
}

process RUDDY_PCA {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/projections", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(matrix)

    output:
    tuple val(meta), path("pca_${meta.id}"), emit: pca
    path "pca_${meta.id}.provenance.json", emit: provenance

    script:
    """
    ruddy -q project pca ${matrix} \\
        --id-column id \\
        --n-components ${meta.n_components} \\
        --scaling ${meta.scaling} \\
        --random-state ${params.seed} \\
        --output-dir pca_${meta.id}
    """
}

process RUDDY_COMPARE {
    tag "${x_name} vs ${y_name}"
    label 'process_medium'
    publishDir "${params.outdir}/comparisons", mode: params.publish_dir_mode

    input:
    tuple val(x_name), path(x_matrix, stageAs: 'x/*'), val(y_name), path(y_matrix, stageAs: 'y/*')

    output:
    path "cmp_${x_name}__${y_name}", emit: comparison
    path "cmp_${x_name}__${y_name}.provenance.json", emit: provenance

    script:
    """
    ruddy -q analyze representation ${x_matrix} ${y_matrix} \\
        --x-id-column id --y-id-column id \\
        --representation-alignment ${params.alignment} \\
        --mantel-permutations ${params.mantel_permutations} \\
        --random-state ${params.seed} \\
        --output-dir cmp_${x_name}__${y_name}
    """
}
