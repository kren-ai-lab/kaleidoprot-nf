nextflow.enable.types = true

// Generate every representation listed in params.representations; VALIDATE has already checked the configs.

include { SYLPHY_ENCODE       } from '../modules/sylphy'
include { SYLPHY_EMBED        } from '../modules/sylphy'
include { ROXY_COMPUTE        } from '../modules/roxy'
include { ERIS_FEATURES       } from '../modules/eris'
include { KPNF_STAGE_MANIFEST } from '../modules/kpnf'
include { Spec                } from './validate'

workflow REPRESENT {
    take:
    reps: Channel<Spec>
    opts: RepresentOptions

    main:
    encoded = SYLPHY_ENCODE(reps.filter { r -> r.tool == 'sylphy-encode' }, opts.input, opts.seq_column)
    embedded = SYLPHY_EMBED(reps.filter { r -> r.tool == 'sylphy-embed' }, opts.input, opts.seq_column, opts.cache_dir)
    computed = ROXY_COMPUTE(reps.filter { r -> r.tool == 'roxy' }, opts.input, opts.seq_column)
    all = encoded.mix(embedded).mix(computed)
    if (opts.structures) {
        staged = KPNF_STAGE_MANIFEST(opts.structures, opts.input, opts.strict)
        all = all.mix(ERIS_FEATURES(reps.filter { r -> r.tool == 'eris' }, staged, opts.structure_files))
    }

    emit:
    // Every representation, including the ones that failed (matrix null, failed set).
    reps: Channel<Representation> = all
}

record RepresentOptions {
    input: Path
    seq_column: String
    cache_dir: String?
    structures: Path?          // Eris manifest
    structure_files: List<Path> // files the manifest points to
    strict: Boolean            // the manifest must have exactly the ids of input
}

record Representation {
    name: String
    tool: String
    matrix: Path?
    provenance: Path?
    artifacts: Path?
    artifacts_provenance: Path?
    failed: Path?
}
