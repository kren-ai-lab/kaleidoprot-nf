// Characterize each representation on its own (EDA + PCA + figure) and compare pairs of
// representation spaces (CCA, CKA, Procrustes, Mantel, distance similarity).

include { RUDDY_EDA ; RUDDY_PCA ; RUDDY_COMPARE } from '../modules/ruddy'
include { KPNF_PLOT                             } from '../modules/kpnf'

workflow CHARACTERIZE {
    take:
    matrices      // channel: [ meta, matrix ]
    labels        // value channel: table with id + label column, or []
    comparisons   // list of [x_name, y_name]

    main:
    RUDDY_EDA(matrices)

    RUDDY_PCA(
        matrices.map { meta, matrix ->
            [[id: meta.name, title: "${meta.name} (${meta.tool})", n_components: params.projection_components,
              scaling: params.projection_scaling], matrix]
        }
    )
    KPNF_PLOT(RUDDY_PCA.out.pca, labels)

    def by_name = matrices.map { meta, matrix -> [meta.name, matrix] }
    def pairs = channel.fromList(comparisons)
        .map { pair -> [pair[0], pair[1]] }
        .combine(by_name, by: 0)                            // [x, y, x_matrix]
        .map { x, y, x_matrix -> [y, x, x_matrix] }
        .combine(by_name, by: 0)                            // [y, x, x_matrix, y_matrix]
        .map { y, x, x_matrix, y_matrix -> [x, x_matrix, y, y_matrix] }
    RUDDY_COMPARE(pairs)

    emit:
    eda = RUDDY_EDA.out.eda                    // channel: [ name, eda_dir ]
    pca = RUDDY_PCA.out.pca                    // channel: [ meta, pca_dir ]
    figures = KPNF_PLOT.out.figure
    comparisons = RUDDY_COMPARE.out.comparison
}
