nextflow.enable.types = true

// Sylphy: sequence encodings and protein language model embeddings.
// Paths go as flags; every other option comes from the representation's --config file.

process SYLPHY_VALIDATE {
    tag name
    label 'process_single'
    container 'ghcr.io/kren-ai-lab/sylphy:1.2.2'

    input:
    record(name: String, tool: String, config: Path)

    output:
    name

    script:
    def target = tool == 'sylphy-embed' ? 'embed' : 'encode'
    """
    sylphy validate-config ${target} ${config} --json > validation.json || { cat validation.json >&2; exit 2; }
    """

    stub:
    """
    true
    """
}

process SYLPHY_ENCODE {
    tag name
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/sylphy:1.2.2'

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
    soft-fail rep_${name} sylphy encode \\
        --config ${config} \\
        -i ${sequences} --id-col id --seq-col ${seq_column} \\
        -o ${name}.parquet \\
        --log-level WARNING
    """

    stub:
    """
    touch ${name}.parquet
    touch ${name}.parquet.provenance.json
    """
}

process SYLPHY_EMBED {
    tag name
    label 'process_gpu'
    container 'ghcr.io/kren-ai-lab/sylphy:1.2.2-full'

    input:
    record(name: String, tool: String, config: Path)
    sequences: Path
    seq_column: String
    cache_dir: String?

    output:
    record(
        name: name,
        tool: tool,
        matrix: file("${name}.parquet", optional: true),
        provenance: file("${name}.parquet.provenance.json", optional: true),
        failed: file("rep_${name}.failed", optional: true)
    )

    script:
    def cache = cache_dir ? "export SYLPHY_CACHE_DIR=${cache_dir}" : ''
    """
    ${cache}
    soft-fail rep_${name} sylphy embed \\
        --config ${config} \\
        -i ${sequences} --id-col id --seq-col ${seq_column} \\
        -o ${name}.parquet \\
        --log-level WARNING
    """

    stub:
    """
    touch ${name}.parquet
    touch ${name}.parquet.provenance.json
    """
}
