// Roxy: sequence-derived descriptors. Descriptor or family selection lives in the --config file.

process ROXY_VALIDATE {
    tag "${meta.name}"
    label 'process_single'
    container 'ghcr.io/kren-ai-lab/roxy:0.4.0'

    input:
    tuple val(meta), path(config)

    output:
    val(meta.name), emit: ok

    script:
    """
    roxy validate-config ${config} --json > validation.json || { cat validation.json >&2; exit 2; }
    """
}

process ROXY_COMPUTE {
    tag "${meta.name}"
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/roxy:0.4.0'
    publishDir "${params.outdir}/representations", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(config)
    path sequences

    output:
    tuple val(meta), path("${meta.name}.parquet"), emit: matrix
    path "${meta.name}.parquet.provenance.json", emit: provenance

    script:
    """
    roxy compute ${sequences} \\
        --config ${config} \\
        --id-col id --seq-col ${params.seq_column} \\
        -o ${meta.name}.parquet \\
        --no-progress
    """
}
