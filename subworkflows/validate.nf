nextflow.enable.types = true

// Check every representation's --config with its tool's validate-config before anything runs.

include { SYLPHY_VALIDATE } from '../modules/sylphy'
include { ROXY_VALIDATE   } from '../modules/roxy'
include { ERIS_VALIDATE   } from '../modules/eris'

workflow VALIDATE {
    take:
    reps: Channel<Spec>

    main:
    sylphy = SYLPHY_VALIDATE(reps.filter { r -> r.tool in ['sylphy-encode', 'sylphy-embed'] })
    roxy = ROXY_VALIDATE(reps.filter { r -> r.tool == 'roxy' })
    eris = ERIS_VALIDATE(reps.filter { r -> r.tool == 'eris' })

    // Releases the representations only once every config passed.
    gate = sylphy.mix(roxy).mix(eris).collect()
    validated = reps.combine(validated: gate)

    emit:
    reps: Channel<Spec> = validated
}

// One entry of params.representations, with its config as a file.
record Spec {
    name: String
    tool: String
    config: Path
    features_source: String?
    pool: String?
}
