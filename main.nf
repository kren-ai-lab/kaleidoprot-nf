#!/usr/bin/env nextflow
/*
 * kaleidoprot-nf: integrates Sylphy, Roxy, Eris and Ruddy.
 *
 *   VALIDATE      check every representation's --config with its tool's validate-config
 *   REPRESENT     generate each representation (fan-out), once every config passed
 *   CHARACTERIZE  Ruddy EDA + PCA + figure per representation, pairwise space comparisons
 *   COMPOSE       one-level compositions: raw / PCA-reduced / selected blocks -> concat -> PCA -> figure
 *   KPNF_REPORT   report.md + summary.json
 */

include { VALIDATE     } from './subworkflows/validate'
include { REPRESENT    } from './subworkflows/represent'
include { CHARACTERIZE } from './subworkflows/characterize'
include { COMPOSE      } from './subworkflows/compose'
include { KPNF_REPORT  } from './modules/kpnf'

workflow {
    def errors = checkParams(params)
    if (errors) {
        error("Invalid parameters:\n  - " + errors.join('\n  - '))
    }

    def reps = channel.fromList(params.representations)
        .map { r ->
            [
                [
                    name: r.name,
                    tool: r.tool,
                    features_source: r.features_source ?: 'auto'
                ],
                file(r.config, checkIfExists: true)
            ]
        }
    def sequences = channel.value(file(params.input, checkIfExists: true))
    def labels = channel.value(params.label_column ? file(params.input) : [])

    def manifest = channel.value([])
    def structures = channel.value([])
    if (params.structures) {
        def manifest_file = file(params.structures, checkIfExists: true)
        def base = manifest_file.parent
        def files = manifest_file
            .splitCsv(header: true)
            .collect { row ->
                def p = row.path.toString()
                p.startsWith('/') ? file(p, checkIfExists: true) : file(base.resolve(p).toString(), checkIfExists: true)
            }
        manifest = channel.value(manifest_file)
        structures = channel.value(files)
    }

    VALIDATE(reps)
    REPRESENT(VALIDATE.out.reps, sequences, manifest, structures)
    CHARACTERIZE(REPRESENT.out.matrices, labels, comparisonPairs(params))
    COMPOSE(REPRESENT.out.matrices, CHARACTERIZE.out.eda, params.compositions ?: [], labels)

    KPNF_REPORT(
        REPRESENT.out.provenance.collect().ifEmpty([]),
        CHARACTERIZE.out.pca.mix(COMPOSE.out.pca).map { _meta, dir -> dir }.collect().ifEmpty([]),
        CHARACTERIZE.out.comparisons.collect().ifEmpty([]),
        COMPOSE.out.selection.collect().ifEmpty([]),
        COMPOSE.out.blocks.collect().ifEmpty([]),
        CHARACTERIZE.out.figures.mix(COMPOSE.out.figures).collect().ifEmpty([]),
    )
}

// Pairs of representation names to compare: 'all', or a list of [x, y].
def comparisonPairs(p) {
    def names = p.representations.collect { r -> r.name }
    if (p.comparisons == 'all') {
        def pairs = []
        names.eachWithIndex { x, i -> names.drop(i + 1).each { y -> pairs << [x, y] } }
        return pairs
    }
    return (p.comparisons ?: []).collect { pair -> pair as List }
}

// Fail before any task runs. Tool-level options are checked by each tool's validate-config.
def checkParams(p) {
    def TOOLS = ['sylphy-encode', 'sylphy-embed', 'roxy', 'eris']
    def NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]*$/
    def errors = []
    if (!p.input) {
        errors << "--input is required (table with columns id and ${p.seq_column})"
    }
    if (!(p.representations instanceof List) || !p.representations) {
        errors << 'representations: give a non-empty list (see examples/test/params.yaml)'
        return errors
    }
    def names = []
    p.representations.eachWithIndex { r, i ->
        def where = "representations[${i}]"
        if (!(r instanceof Map)) {
            errors << "${where}: expected a map with name, tool and config"
            return null
        }
        if (!(r.name ==~ NAME_PATTERN) || r.name.contains('__')) {
            errors << "${where}: name '${r.name}' must match ${NAME_PATTERN} and not contain '__'"
        }
        if (r.name in names) {
            errors << "${where}: duplicated name '${r.name}'"
        }
        names << r.name
        if (!(r.tool in TOOLS)) {
            errors << "${where}: tool '${r.tool}' is not one of ${TOOLS.join(', ')}"
        }
        if (!r.config) {
            errors << "${where}: config is required (the tool's --config file)"
        }
        if (r.tool == 'eris' && !p.structures) {
            errors << "${where}: Eris needs --structures (manifest with id,path[,chain,model])"
        }
    }
    comparisonPairs(p).each { pair ->
        if (pair.size() != 2 || pair[0] == pair[1] || !(pair[0] in names) || !(pair[1] in names)) {
            errors << "comparisons: ${pair} must name two different representations"
        }
    }
    def comp_names = []
    (p.compositions ?: []).eachWithIndex { c, i ->
        def where = "compositions[${i}]"
        if (!(c.name ==~ NAME_PATTERN) || c.name.contains('__') || c.name in names || c.name in comp_names) {
            errors << "${where}: name '${c.name}' must be valid, unique and differ from representation names"
        }
        comp_names << c.name
        if (!(c.blocks instanceof List) || c.blocks.size() < 2) {
            errors << "${where}: blocks needs at least two entries"
            return null
        }
        def used = []
        c.blocks.eachWithIndex { b, j ->
            if (!(b.representation in names)) {
                errors << "${where}.blocks[${j}]: unknown representation '${b.representation}'"
            }
            if (b.representation in used) {
                errors << "${where}.blocks[${j}]: '${b.representation}' used twice in one composition"
            }
            used << b.representation
            if (b.reduce && b.select) {
                errors << "${where}.blocks[${j}]: use either reduce or select, not both"
            }
            if (b.reduce && !(b.reduce instanceof Integer && b.reduce > 0)) {
                errors << "${where}.blocks[${j}]: reduce must be a positive number of PCA components"
            }
        }
        if (c.scaling && !(c.scaling in ['none', 'standard', 'block'])) {
            errors << "${where}: scaling must be none, standard or block"
        }
    }
    if (!(p.alignment in ['strict', 'partial'])) {
        errors << 'alignment must be strict or partial'
    }
    return errors
}
