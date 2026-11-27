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

include { checkParams ; comparisonPairs ; inlineConfig } from './utils'

workflow {
    def errors = checkParams(params)
    if (errors) {
        error("Invalid parameters:\n  - " + errors.join('\n  - '))
    }

    if (params.cache_dir) {
        file(params.cache_dir).mkdirs() // a missing bind-mount source fails (apptainer) or is created by root (docker)
    }

    def reps = channel.fromList(params.representations)
        .map { r ->
            [
                [
                    name: r.name,
                    tool: r.tool,
                    features_source: r.features_source ?: 'auto'
                ],
                r.config instanceof Map ? inlineConfig(r.name, r.config) : file(r.config, checkIfExists: true)
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
        REPRESENT.out.failed.mix(CHARACTERIZE.out.failed, COMPOSE.out.failed).collect().ifEmpty([]),
    )
}
