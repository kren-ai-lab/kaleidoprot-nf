nextflow.enable.types = true

// kpnf: glue that belongs to the pipeline rather than to any single library
// (feature selection, block concatenation, scaling, plots, report).

// Image tag: the pipeline version, or `main` (built from the main branch) on a dev version.
def kpnfTag() {
    def v = workflow.manifest.version
    v.contains('dev') ? 'main' : v
}

process KPNF_STAGE_MANIFEST {
    label 'process_single'
    container "ghcr.io/kren-ai-lab/kpnf:${kpnfTag()}"

    input:
    manifest: Path
    input: Path
    strict: Boolean

    output:
    file('manifest.local.csv')

    script:
    // Manifest paths are rewritten to the staged files; Eris resolves them against the CWD.
    def check = strict ? "--input ${input}" : ''
    """
    kpnf stage-manifest ${manifest} --prefix structures/ --out manifest.local.csv ${check} > /dev/null
    """

    stub:
    """
    touch manifest.local.csv
    """
}

process KPNF_SELECT {
    tag "${comp}:${rep}"
    label 'process_single'
    container "ghcr.io/kren-ai-lab/kpnf:${kpnfTag()}"

    input:
    record(comp: String, rep: String, index: Integer, size: Integer, matrix: Path, eda: Path)
    selection: Map

    output:
    record(
        comp: comp,
        rep: rep,
        index: index,
        size: size,
        selected: file("${comp}__${rep}.selected.parquet"),
        report: file("${comp}__${rep}.selection.csv"),
        provenance: file("${comp}__${rep}.selected.parquet.provenance.json")
    )

    script:
    def cap = selection.max_features ? "--max-features ${selection.max_features}" : ''
    """
    kpnf select ${matrix} \\
        --eda-dir ${eda} \\
        --out ${comp}__${rep}.selected.parquet \\
        --report ${comp}__${rep}.selection.csv \\
        --max-missing ${selection.max_missing} \\
        --near-constant ${selection.near_constant} \\
        --abs-rho ${selection.abs_rho} \\
        --method ${selection.method} ${cap}
    """

    stub:
    """
    touch ${comp}__${rep}.selected.parquet
    touch ${comp}__${rep}.selection.csv
    touch ${comp}__${rep}.selected.parquet.provenance.json
    """
}

process KPNF_CONCAT {
    tag name
    label 'process_single'
    container "ghcr.io/kren-ai-lab/kpnf:${kpnfTag()}"

    input:
    record(name: String, scaling: String, alignment: String, reps: List<String>, blocks: List<Path>)

    stage:
    stageAs blocks, 'blocks/?/*'

    output:
    record(
        name: name,
        matrix: file("${name}.parquet"),
        blocks: file("${name}.blocks.json"),
        provenance: file("${name}.parquet.provenance.json")
    )

    script:
    // Each block is staged as blocks/<n>/<file>, so blocks that share a file name do not collide.
    def args = (0..<reps.size()).collect { i -> "--block ${reps[i]}=${blocks[i]}" }.join(' ')
    """
    kpnf concat ${args} \\
        --out ${name}.parquet \\
        --scaling ${scaling} \\
        --alignment ${alignment}
    """

    stub:
    """
    touch ${name}.parquet
    touch ${name}.blocks.json
    touch ${name}.parquet.provenance.json
    """
}

process KPNF_PLOT {
    tag id
    label 'process_single'
    container "ghcr.io/kren-ai-lab/kpnf:${kpnfTag()}"

    input:
    record(id: String, title: String, pca: Path)
    labels: Path?
    label_column: String?

    output:
    record(
        id: id,
        figure: file("${id}.png", optional: true),
        provenance: file("${id}.png.provenance.json", optional: true),
        failed: file("figure_${id}.failed", optional: true)
    )

    script:
    def colour = labels && label_column ? "--labels ${labels} --label-column ${label_column}" : ''
    """
    soft-fail figure_${id} kpnf plot ${pca} --out ${id}.png --title '${title}' ${colour}
    """

    stub:
    """
    touch ${id}.png
    touch ${id}.png.provenance.json
    """
}

process KPNF_REPORT {
    label 'process_single'
    container "ghcr.io/kren-ai-lab/kpnf:${kpnfTag()}"

    input:
    representations: Bag<Path>
    projections: Bag<Path>
    comparisons: Bag<Path>
    selection: Bag<Path>
    compositions: Bag<Path>
    figures: Bag<Path>
    failed: Bag<Path>

    stage:
    stageAs representations, 'results/representations/*'
    stageAs projections, 'results/projections/*'
    stageAs comparisons, 'results/comparisons/*'
    stageAs selection, 'results/selection/*'
    stageAs compositions, 'results/compositions/*'
    stageAs figures, 'results/figures/*'
    stageAs failed, 'results/failed/*'

    output:
    file('report')

    script:
    """
    kpnf report results --out-dir report > /dev/null
    """

    stub:
    """
    mkdir -p report
    """
}
