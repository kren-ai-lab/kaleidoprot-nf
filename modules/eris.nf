// Eris: structure-based representations.
// One task runs batch encode -> pack -> features, so the matrix that leaves this module is the
// structure-level feature table (id + features). The native artifacts are published for reuse.

process ERIS_VALIDATE {
    tag "${meta.name}"
    label 'process_single'

    input:
    tuple val(meta), path(config)

    output:
    val(meta.name), emit: ok

    script:
    """
    eris validate-config batch-encode ${config} --json > validation.json || { cat validation.json >&2; exit 2; }
    """
}

process ERIS_FEATURES {
    tag "${meta.name}"
    label 'process_medium'
    publishDir "${params.outdir}/representations", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(config)
    path manifest
    path structures, stageAs: 'structures/*'

    output:
    tuple val(meta), path("${meta.name}.csv"), emit: matrix
    path "${meta.name}.csv.provenance.json", emit: provenance
    path "${meta.name}_artifacts", emit: artifacts
    path "${meta.name}_artifacts.provenance.json", emit: artifacts_provenance

    script:
    def source = meta.features_source && meta.features_source != 'auto' ? "--source ${meta.features_source}" : ''
    """
    # Manifest paths are rewritten to the staged files; Eris resolves them against the CWD.
    kpnf stage-manifest ${manifest} --prefix structures/ --out manifest.local.csv > /dev/null

    eris batch encode manifest.local.csv --config ${config} --out ${meta.name}_artifacts
    eris pack ${meta.name}_artifacts --out ${meta.name}_artifacts/index.csv
    eris features ${meta.name}_artifacts/index.csv --out ${meta.name}.csv ${source}
    """
}
