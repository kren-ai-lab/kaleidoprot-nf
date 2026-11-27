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

nextflow.enable.types = true

include { paramsHelp ; validateParameters } from 'plugin/nf-schema'
include { checkParams ; comparisonPairs ; inlineConfig ; structureFiles } from './utils'

include { VALIDATE           } from './subworkflows/validate'
include { REPRESENT          } from './subworkflows/represent'
include { CHARACTERIZE       } from './subworkflows/characterize'
include { COMPOSE            } from './subworkflows/compose'
include { KPNF_REPORT        } from './modules/kpnf'

// Described in nextflow_schema.json (see --help). outdir and publish_dir_mode only affect the config.
params {
    // Inputs
    input: Path?
    seq_column: String = 'sequence'
    label_column: String?
    structures: Path?

    // Workflow definition (normally given with -params-file, see examples/test/params.yaml)
    representations: List<Map> = []
    compositions: List<Map> = []
    comparisons: List<List<String>>?

    // Analysis options
    alignment: String = 'strict'
    projection_components: Integer = 2
    comparison_components: Integer = 5
    projection_scaling: String = 'standard'
    mantel_permutations: Integer = 999
    eda_max_columns: Integer = 5000
    seed: Integer = 0
    selection: Map = [max_missing: 0.0, near_constant: 0.99, abs_rho: 0.90, method: 'spearman', max_features: null]

    // persistent cache for downloaded models. By default each task downloads its own
    cache_dir: String?
    help: Boolean
}

workflow {

    main:
    if (params.help) {
        log.info(
            paramsHelp(
                parameter: params.help.toString() in ['true', 'false'] ? null : params.help,
                command: 'nextflow run kren-ai-lab/kaleidoprot-nf -profile docker -params-file params.yaml',
            )
        )
        exit(0, '')
    }
    validateParameters()
    def errors = checkParams(params)
    if (errors) {
        error("Invalid parameters:\n  - " + errors.join('\n  - '))
    }
    if (params.cache_dir) {
        file(params.cache_dir).mkdirs() // a missing bind-mount source fails (apptainer) or is created by root (docker)
    }

    specs = channel.fromList(params.representations)
        .map { r ->
            record(
                name: r.name as String,
                tool: r.tool as String,
                config: r.config instanceof Map ? inlineConfig(r.name, r.config) : file(r.config as String, checkIfExists: true),
                features_source: r.features_source as String,
                pool: r.pool as String,
            )
        }
    validated = VALIDATE(specs)
    all_reps = REPRESENT(
        validated,
        record(
            input: params.input,
            seq_column: params.seq_column,
            cache_dir: params.cache_dir,
            structures: params.structures,
            structure_files: params.structures ? structureFiles(params.structures) : [],
            strict: params.alignment == 'strict',
        ),
    )
    reps = all_reps.filter { r -> r.matrix != null }

    labels = params.label_column ? params.input : null
    characterized = CHARACTERIZE(
        reps,
        comparisonPairs(params),
        record(
            comparison_components: params.comparison_components,
            projection_scaling: params.projection_scaling,
            eda_max_columns: params.eda_max_columns,
            mantel_permutations: params.mantel_permutations,
            alignment: params.alignment,
            seed: params.seed,
            labels: labels,
            label_column: params.label_column,
        ),
    )
    composed = COMPOSE(
        reps,
        characterized.eda,
        params.compositions,
        record(
            selection: params.selection,
            alignment: params.alignment,
            projection_components: params.projection_components,
            seed: params.seed,
            labels: labels,
            label_column: params.label_column,
        ),
    )

    // A run without any representation is a failure, not an empty report.
    all_reps
        .collect()
        .subscribe { rs ->
            if (rs.every { r -> r.matrix == null }) {
                def reasons = rs.collect { r -> "${r.name}: ${r.failed?.text?.trim()?.readLines()?.last()}" }
                error("No representation could be generated:\n  - " + reasons.join('\n  - '))
            }
        }

    eda = characterized.eda.filter { e -> e.eda != null }
    projections = characterized.pca.mix(composed.pca).filter { p -> p.pca != null }
    comparisons = characterized.comparisons.filter { c -> c.comparison != null }
    figures = characterized.figures.mix(composed.figures).filter { f -> f.figure != null }
    failed = all_reps
        .map { r -> r.failed }
        .mix(characterized.eda.map { e -> e.failed })
        .mix(characterized.pca.map { p -> p.failed })
        .mix(characterized.figures.map { f -> f.failed })
        .mix(characterized.comparisons.map { c -> c.failed })
        .mix(composed.pca.map { p -> p.failed })
        .mix(composed.figures.map { f -> f.failed })
        .filter { f -> f != null }
    report = KPNF_REPORT(
        reps.map { r -> r.provenance }.collect(),
        projections.map { p -> p.pca }.collect(),
        comparisons.map { c -> c.comparison }.collect(),
        composed.selection.map { s -> s.report }.collect(),
        composed.compositions.map { c -> c.blocks }.collect(),
        figures.map { f -> f.figure }.collect(),
        failed.collect(),
    )

    publish:
    representations = reps.map { r ->
        record(matrix: r.matrix, provenance: r.provenance, artifacts: r.artifacts, artifacts_provenance: r.artifacts_provenance)
    }
    eda             = eda.map { e -> record(eda: e.eda, provenance: e.provenance) }
    projections     = projections.map { p -> record(pca: p.pca, provenance: p.provenance) }
    comparisons     = comparisons.map { c -> record(comparison: c.comparison, provenance: c.provenance) }
    selection       = composed.selection.map { s -> record(selected: s.selected, report: s.report, provenance: s.provenance) }
    compositions    = composed.compositions.map { c -> record(matrix: c.matrix, blocks: c.blocks, provenance: c.provenance) }
    figures         = figures.map { f -> record(figure: f.figure, provenance: f.provenance) }
    report          = report
}

output {
    representations {
        path 'representations'
    }
    eda {
        path 'eda'
    }
    projections {
        path 'projections'
    }
    comparisons {
        path 'comparisons'
    }
    selection {
        path 'selection'
    }
    compositions {
        path 'compositions'
    }
    figures {
        path 'figures'
    }
    report {
        path '.'
    }
}
