nextflow.enable.types = true

// Roxy: sequence-derived descriptors. Descriptor or family selection lives in the --config file.

process ROXY_VALIDATE {
    tag name
    label 'process_single'
    container 'ghcr.io/kren-ai-lab/roxy:0.4.0'

    input:
    record(name: String, config: Path)

    output:
    name

    script:
    """
    roxy validate-config ${config} --json > validation.json || { cat validation.json >&2; exit 2; }
    """

    stub:
    """
    true
    """
}

process ROXY_COMPUTE {
    tag name
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/roxy:0.4.0'

    input:
    record(name: String, tool: String, config: Path)
    sequences: Path
    seq_column: String

    output:
    record(
        name: name,
        tool: tool,
        matrix: file("${name}.parquet", optional: true),
        provenance: file("${name}.parquet.provenance.json", optional: true),
        failed: file("rep_${name}.failed", optional: true)
    )

    script:
    """
    soft-fail rep_${name} roxy compute ${sequences} \\
        --config ${config} \\
        --id-col id --seq-col ${seq_column} \\
        -o ${name}.parquet \\
        --no-progress
    """

    stub:
    """
    touch ${name}.parquet
    touch ${name}.parquet.provenance.json
    """
}
