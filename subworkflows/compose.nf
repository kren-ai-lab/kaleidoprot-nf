// One-level composition: each block is taken raw, reduced with a Ruddy PCA, or filtered with kpnf
// select (driven by the block's Ruddy EDA); blocks are then aligned by id, prefixed and scaled
// (kpnf concat), projected with Ruddy and plotted. Nested compositions are out of scope here.

include { RUDDY_PCA as RUDDY_PCA_BLOCK    } from '../modules/ruddy'
include { RUDDY_PCA as RUDDY_PCA_COMPOSED } from '../modules/ruddy'
include { KPNF_SELECT                     } from '../modules/kpnf'
include { KPNF_CONCAT                     } from '../modules/kpnf'
include { KPNF_PLOT                       } from '../modules/kpnf'

workflow COMPOSE {
    take:
    matrices     // channel: [ meta, matrix ]
    eda          // channel: [ name, eda_dir ]
    compositions // list of maps (params.compositions)
    labels       // value channel: table with id + label column, or []

    main:
    def by_name = matrices.map { meta, matrix -> [meta.name, matrix] }

    def block_specs = channel.fromList(compositions)
        .flatMap { comp ->
            comp.blocks
                .withIndex()
                .collect { b, i ->
                    [
                        b.representation,
                        [
                            comp: comp.name,
                            index: i,
                            size: comp.blocks.size(),
                            rep: b.representation,
                            reduce: b.reduce ?: 0,
                            reduce_scaling: b.reduce_scaling ?: 'none',
                            select: b.select ?: false
                        ]
                    ]
                }
        }
        .combine(by_name, by: 0) // [rep, block, matrix]
        .branch { _rep, block, _matrix ->
            reduce: block.reduce
            select: block.select
            raw: true
        }

    RUDDY_PCA_BLOCK(
        block_specs.reduce.map { rep, block, matrix ->
            [
                [
                    id: "block__${block.comp}__${rep}",
                    n_components: block.reduce,
                    scaling: block.reduce_scaling,
                    block: block
                ],
                matrix
            ]
        }
    )
    KPNF_SELECT(
        // [rep, block, matrix, eda_dir]
        block_specs.select.combine(eda, by: 0).map { _rep, block, matrix, eda_dir -> [block, matrix, eda_dir] }
    )

    def comp_by_name = compositions.collectEntries { comp -> [comp.name, comp] }
    def prepared = RUDDY_PCA_BLOCK.out.pca
        .map { meta, pca_dir -> [meta.block, pca_dir.resolve('pca_scores.csv')] }
        .mix(KPNF_SELECT.out.matrix, block_specs.raw.map { _rep, block, matrix -> [block, matrix] })
        .map { block, file -> [groupKey(block.comp, block.size), block.index, block.rep, file] }
        .groupTuple()
        .map { comp, indices, reps, files ->
            def order = (0..<indices.size()).toList().sort { k -> indices[k] }
            [comp_by_name[comp.toString()], order.collect { k -> reps[k] }, order.collect { k -> files[k] }]
        }
    KPNF_CONCAT(prepared)

    RUDDY_PCA_COMPOSED(
        KPNF_CONCAT.out.matrix.map { comp, matrix ->
            [
                [
                    id: "comp__${comp.name}",
                    title: "composition ${comp.name}",
                    n_components: comp.n_components ?: params.projection_components,
                    scaling: 'none'
                ],
                matrix
            ]
        }
    )
    KPNF_PLOT(RUDDY_PCA_COMPOSED.out.pca, labels)

    emit:
    pca       = RUDDY_PCA_BLOCK.out.pca.mix(RUDDY_PCA_COMPOSED.out.pca) // channel: [ meta, pca_dir ]
    selection = KPNF_SELECT.out.report
    blocks    = KPNF_CONCAT.out.blocks
    figures   = KPNF_PLOT.out.figure
    failed    = RUDDY_PCA_BLOCK.out.failed.mix(RUDDY_PCA_COMPOSED.out.failed, KPNF_PLOT.out.failed)
}
