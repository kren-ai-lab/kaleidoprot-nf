// Sylphy: sequence encodings and protein language model embeddings.
// Paths go as flags; every other option comes from the representation's --config file.

process SYLPHY_VALIDATE {
    tag "${meta.name}"
    label 'process_single'
    container 'ghcr.io/kren-ai-lab/sylphy:1.2.1'

    input:
    tuple val(meta), path(config)

    output:
    val(meta.name), emit: ok

    script:
    def target = meta.tool == 'sylphy-embed' ? 'embed' : 'encode'
    """
    sylphy validate-config ${target} ${config} --json > validation.json || { cat validation.json >&2; exit 2; }
    """

    stub:
    """
    true
    """
}

process SYLPHY_ENCODE {
    tag "${meta.name}"
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/sylphy:1.2.1'
    publishDir "${params.outdir}/representations", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(config)
    path sequences

    output:
    tuple val(meta), path("${meta.name}.parquet"), optional: true, emit: matrix
    path "${meta.name}.parquet.provenance.json", optional: true, emit: provenance
    path "rep_${meta.name}.failed", optional: true, emit: failed

    script:
    """
    soft-fail rep_${meta.name} sylphy encode \\
        --config ${config} \\
        -i ${sequences} --id-col id --seq-col ${params.seq_column} \\
        -o ${meta.name}.parquet \\
        --log-level WARNING
    """

    stub:
    """
    touch ${meta.name}.parquet
    touch ${meta.name}.parquet.provenance.json
    """
}

process SYLPHY_EMBED {
    tag "${meta.name}"
    label 'process_gpu'
    container 'ghcr.io/kren-ai-lab/sylphy:1.2.1-full'
    publishDir "${params.outdir}/representations", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(config)
    path sequences

    output:
    tuple val(meta), path("${meta.name}.parquet"), optional: true, emit: matrix
    path "${meta.name}.parquet.provenance.json", optional: true, emit: provenance
    path "rep_${meta.name}.failed", optional: true, emit: failed

    script:
    def cache = params.cache_dir ? "export SYLPHY_CACHE_DIR=${params.cache_dir}" : ''
    """
    ${cache}
    soft-fail rep_${meta.name} sylphy embed \\
        --config ${config} \\
        -i ${sequences} --id-col id --seq-col ${params.seq_column} \\
        -o ${meta.name}.parquet \\
        --log-level WARNING
    """

    stub:
    """
    touch ${meta.name}.parquet
    touch ${meta.name}.parquet.provenance.json
    """
}
