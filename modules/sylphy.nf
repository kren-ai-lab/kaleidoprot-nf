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
    tuple val(meta), path("${meta.name}.parquet"), emit: matrix
    path "${meta.name}.parquet.provenance.json", emit: provenance

    script:
    """
    sylphy encode \\
        --config ${config} \\
        -i ${sequences} --id-col id --seq-col ${params.seq_column} \\
        -o ${meta.name}.parquet \\
        --log-level WARNING
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
    tuple val(meta), path("${meta.name}.parquet"), emit: matrix
    path "${meta.name}.parquet.provenance.json", emit: provenance

    script:
    """
    sylphy embed \\
        --config ${config} \\
        -i ${sequences} --id-col id --seq-col ${params.seq_column} \\
        -o ${meta.name}.parquet \\
        --log-level WARNING
    """
}
