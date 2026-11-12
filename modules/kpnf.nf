// kpnf: glue that belongs to KaleidoProt rather than to any single library
// (feature selection, block concatenation, scaling, plots, report).

process KPNF_SELECT {
    tag "${block.comp}:${block.rep}"
    label 'process_single'
    publishDir "${params.outdir}/selection", mode: params.publish_dir_mode

    input:
    tuple val(block), path(matrix), path(eda_dir)

    output:
    tuple val(block), path("${block.comp}__${block.rep}.selected.parquet"), emit: matrix
    path "${block.comp}__${block.rep}.selection.csv", emit: report
    path "${block.comp}__${block.rep}.selected.parquet.provenance.json", emit: provenance

    script:
    def s = params.selection
    def cap = s.max_features ? "--max-features ${s.max_features}" : ''
    """
    kpnf select ${matrix} \\
        --eda-dir ${eda_dir} \\
        --out ${block.comp}__${block.rep}.selected.parquet \\
        --report ${block.comp}__${block.rep}.selection.csv \\
        --max-missing ${s.max_missing} \\
        --near-constant ${s.near_constant} \\
        --abs-rho ${s.abs_rho} \\
        --method ${s.method} ${cap}
    """
}

process KPNF_CONCAT {
    tag "${comp.name}"
    label 'process_single'
    publishDir "${params.outdir}/compositions", mode: params.publish_dir_mode

    input:
    tuple val(comp), val(names), path(blocks, stageAs: 'blocks/?/*')

    output:
    tuple val(comp), path("${comp.name}.parquet"), emit: matrix
    path "${comp.name}.blocks.json", emit: blocks
    path "${comp.name}.parquet.provenance.json", emit: provenance

    script:
    def args = [names, blocks instanceof List ? blocks : [blocks]].transpose().collect { n, f -> "--block ${n}=${f}" }.join(' ')
    """
    kpnf concat ${args} \\
        --out ${comp.name}.parquet \\
        --scaling ${comp.scaling ?: 'block'} \\
        --alignment ${comp.alignment ?: params.alignment}
    """
}

process KPNF_PLOT {
    tag "${meta.id}"
    label 'process_single'
    publishDir "${params.outdir}/figures", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(pca_dir)
    path labels

    output:
    path "${meta.id}.png", emit: figure
    path "${meta.id}.png.provenance.json", emit: provenance

    script:
    def colour = labels && params.label_column ? "--labels ${labels} --label-column ${params.label_column}" : ''
    """
    kpnf plot ${pca_dir} --out ${meta.id}.png --title '${meta.title ?: meta.id}' ${colour}
    """
}

process KPNF_REPORT {
    label 'process_single'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path representations, stageAs: 'results/representations/*'
    path projections, stageAs: 'results/projections/*'
    path comparisons, stageAs: 'results/comparisons/*'
    path selection, stageAs: 'results/selection/*'
    path compositions, stageAs: 'results/compositions/*'
    path figures, stageAs: 'results/figures/*'

    output:
    path "report", emit: report

    script:
    """
    kpnf report results --out-dir report > /dev/null
    """
}
