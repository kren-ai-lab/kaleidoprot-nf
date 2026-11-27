nextflow.enable.types = true

// Characterize each representation on its own (EDA + PCA + figure) and compare pairs of
// representation spaces (CCA, CKA, Procrustes, Mantel, distance similarity) on their PCA scores.

include { RUDDY_EDA      } from '../modules/ruddy'
include { RUDDY_PCA      } from '../modules/ruddy'
include { RUDDY_COMPARE  } from '../modules/ruddy'
include { KPNF_PLOT      } from '../modules/kpnf'
include { Representation } from './represent'

workflow CHARACTERIZE {
    take:
    reps: Channel<Representation> // only the ones with a matrix
    pairs: List<List<String>>     // [x_name, y_name]
    opts: AnalysisOptions

    main:
    eda = RUDDY_EDA(reps, opts.eda_max_columns)

    pca = RUDDY_PCA(
        reps.map { r ->
            record(
                id: r.name,
                title: "${r.name} (${r.tool})",
                n_components: opts.comparison_components,
                scaling: opts.projection_scaling,
                matrix: r.matrix
            )
        },
        opts.seed
    )
    done = pca.filter { p -> p.pca != null }
    figures = KPNF_PLOT(done, opts.labels, opts.label_column)

    // Raw matrices make CCA degenerate (features >= samples), let large-magnitude columns dominate CKA and
    // Mantel, and rule out Procrustes (different widths); standardized PCA scores of equal width avoid all three.
    scores = done.map { p -> record(name: p.id, scores: p.pca.resolve('pca_scores.csv')) }
    compared = RUDDY_COMPARE(
        channel.fromList(pairs)
            .map { pair -> record(x: pair[0], y: pair[1]) }
            .join(scores.map { s -> record(x: s.name, x_scores: s.scores) }, by: 'x')
            .join(scores.map { s -> record(y: s.name, y_scores: s.scores) }, by: 'y'),
        opts.comparison_components,
        opts.alignment,
        opts.mantel_permutations,
        opts.seed
    )

    emit:
    eda: Channel<Eda> = eda
    pca: Channel<Record> = pca             // id, title, pca, provenance, failed
    figures: Channel<Record> = figures     // id, figure, provenance, failed
    comparisons: Channel<Record> = compared // x, y, comparison, provenance, failed
}

record AnalysisOptions {
    comparison_components: Integer
    projection_scaling: String
    eda_max_columns: Integer
    mantel_permutations: Integer
    alignment: String
    seed: Integer
    labels: Path?        // table with id + label column
    label_column: String?
}

record Eda {
    name: String
    eda: Path?
    provenance: Path?
    failed: Path?
}
