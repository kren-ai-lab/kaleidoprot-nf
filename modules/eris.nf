nextflow.enable.types = true

// Eris: structure-based representations.
// One task runs batch encode -> pack -> features, so the matrix that leaves this module is the
// structure-level feature table (id + features). The native artifacts are published for reuse.

process ERIS_VALIDATE {
    tag name
    label 'process_single'
    container 'ghcr.io/kren-ai-lab/eris:0.3.0'

    input:
    record(name: String, config: Path)

    output:
    name

    script:
    """
    eris validate-config batch-encode ${config} --json > validation.json || { cat validation.json >&2; exit 2; }
    """

    stub:
    """
    true
    """
}

process ERIS_FEATURES {
    tag name
    label 'process_medium'
    container 'ghcr.io/kren-ai-lab/eris:0.3.0'

    input:
    record(name: String, tool: String, config: Path, features_source: String?, pool: String?)
    manifest: Path // staged by KPNF_STAGE_MANIFEST: paths point under structures/
    structures: List<Path>

    stage:
    stageAs structures, 'structures/*'

    output:
    record(
        name: name,
        tool: tool,
        matrix: file("${name}.csv", optional: true),
        provenance: file("${name}.csv.provenance.json", optional: true),
        artifacts: file("${name}_artifacts", optional: true),
        artifacts_provenance: file("${name}_artifacts.provenance.json", optional: true),
        failed: file("rep_${name}.failed", optional: true)
    )

    script:
    def source = features_source && features_source != 'auto' ? "--source ${features_source}" : ''
    def pooling = pool ? "--pool ${pool}" : ''
    """
    soft-fail rep_${name} eris batch encode ${manifest} --config ${config} --out ${name}_artifacts
    [ -e rep_${name}.failed ] || soft-fail rep_${name} eris pack ${name}_artifacts --out ${name}_artifacts/index.csv
    [ -e rep_${name}.failed ] || soft-fail rep_${name} eris features ${name}_artifacts/index.csv --out ${name}.csv ${source} ${pooling}
    """

    stub:
    """
    touch ${name}.csv
    touch ${name}.csv.provenance.json
    mkdir -p ${name}_artifacts
    touch ${name}_artifacts.provenance.json
    """
}
