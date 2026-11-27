nextflow.enable.types = true

// One-level composition: each block is taken raw, reduced with a Ruddy PCA, or filtered with kpnf
// select (driven by the block's Ruddy EDA); blocks are then aligned by id, prefixed and scaled
// (kpnf concat), projected with Ruddy and plotted. Nested compositions are out of scope here.
// A composition is skipped when one of its blocks could not be reduced or has no EDA (the report lists why).

include { RUDDY_PCA as RUDDY_PCA_BLOCK    } from '../modules/ruddy'
include { RUDDY_PCA as RUDDY_PCA_COMPOSED } from '../modules/ruddy'
include { KPNF_SELECT                     } from '../modules/kpnf'
include { KPNF_CONCAT                     } from '../modules/kpnf'
include { KPNF_PLOT                       } from '../modules/kpnf'
include { Representation                  } from './represent'
include { Eda                             } from './characterize'

workflow COMPOSE {
    take:
    reps: Channel<Representation> // only the ones with a matrix
    eda: Channel<Eda>
    compositions: List<Map>       // params.compositions
    opts: ComposeOptions

    main:
    blocks = channel.fromList(blocksOf(compositions))
        .join(reps.map { r -> record(rep: r.name, matrix: r.matrix) }, by: 'rep')

    to_reduce = blocks
        .filter { b -> b.reduce > 0 }
        .map { b ->
            def id = "block__${b.comp}__${b.rep}"
            record(
                id: id,
                title: id,
                comp: b.comp,
                rep: b.rep,
                index: b.index,
                size: b.size,
                n_components: b.reduce,
                scaling: b.reduce_scaling,
                matrix: b.matrix,
            )
        }
    reduced = RUDDY_PCA_BLOCK(to_reduce, opts.seed)

    to_select = blocks
        .filter { b -> b.reduce == 0 && b.select }
        .join(eda.map { e -> record(rep: e.name, eda: e.eda) }, by: 'rep')
    selected = KPNF_SELECT(to_select.filter { b -> b.eda != null }, opts.selection)

    // Every block reaches its group, with file null when it could not be prepared, so groupBy sees complete groups.
    parts = to_reduce
        .join(reduced.map { p -> record(id: p.id, pca: p.pca) }, by: 'id')
        .map { b -> tuple(b.comp, b.size, record(index: b.index, rep: b.rep, file: b.pca?.resolve('pca_scores.csv'))) }
        .mix(selected.map { s -> tuple(s.comp, s.size, record(index: s.index, rep: s.rep, file: s.selected)) })
        .mix(to_select.filter { b -> b.eda == null }.map { b -> tuple(b.comp, b.size, record(index: b.index, rep: b.rep, file: null as Path?)) })
        .mix(blocks.filter { b -> b.reduce == 0 && !b.select }.map { b -> tuple(b.comp, b.size, record(index: b.index, rep: b.rep, file: b.matrix)) })
    settings = compositionsOf(compositions, opts)
    prepared = parts
        .groupBy()
        .filter { _comp, group -> group.every { p -> p.file != null } }
        .map { comp, group ->
            def c = settings.find { s -> s.name == comp }
            def ordered = group.toSorted { p -> p.index }
            record(
                name: c.name,
                scaling: c.scaling,
                alignment: c.alignment,
                n_components: c.n_components,
                reps: ordered.collect { p -> p.rep }.toList(),
                blocks: ordered.collect { p -> p.file }.toList(),
            )
        }
    concatenated = KPNF_CONCAT(prepared)

    composed = RUDDY_PCA_COMPOSED(
        concatenated.join(prepared.map { c -> record(name: c.name, n_components: c.n_components) }, by: 'name').map { c ->
            record(
                id: "comp__${c.name}",
                title: "composition ${c.name}",
                n_components: c.n_components,
                scaling: 'none',
                matrix: c.matrix,
            )
        },
        opts.seed,
    )
    figures = KPNF_PLOT(composed.filter { p -> p.pca != null }, opts.labels, opts.label_column)

    emit:
    pca: Channel<Record> = reduced.mix(composed) // id, title, pca, provenance, failed
    selection: Channel<Record> = selected        // comp, rep, selected, report, provenance, ...
    compositions: Channel<Record> = concatenated // name, matrix, blocks, provenance
    figures: Channel<Record> = figures           // id, figure, provenance, failed
}

record ComposeOptions {
    selection: Map
    alignment: String
    projection_components: Integer
    seed: Integer
    labels: Path?
    label_column: String?
}

record Block {
    comp: String
    rep: String
    index: Integer
    size: Integer
    reduce: Integer        // 0: not reduced
    reduce_scaling: String
    select: Boolean
}

record Composition {
    name: String
    scaling: String
    alignment: String
    n_components: Integer
}

def blocksOf(compositions: List<Map>) -> List<Block> {
    compositions
        .collectMany { comp ->
            comp.blocks
                .withIndex()
                .collect { b, i ->
                    record(
                        comp: comp.name as String,
                        rep: b.representation as String,
                        index: i,
                        size: comp.blocks.size(),
                        reduce: (b.reduce ?: 0) as Integer,
                        reduce_scaling: (b.reduce_scaling ?: 'none') as String,
                        select: (b.select ?: false) as Boolean,
                    )
                }
        }
        .toList()
}

def compositionsOf(compositions: List<Map>, opts: ComposeOptions) -> List<Composition> {
    compositions
        .collect { c ->
            record(
                name: c.name as String,
                scaling: (c.scaling ?: 'block') as String,
                alignment: (c.alignment ?: opts.alignment) as String,
                n_components: (c.n_components ?: opts.projection_components) as Integer,
            )
        }
        .toList()
}
