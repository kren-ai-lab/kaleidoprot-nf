// Generate every representation listed in params.representations; VALIDATE has already checked the configs.

include { SYLPHY_ENCODE ; SYLPHY_EMBED } from '../modules/sylphy'
include { ROXY_COMPUTE                 } from '../modules/roxy'
include { ERIS_FEATURES                } from '../modules/eris'
include { KPNF_STAGE_MANIFEST          } from '../modules/kpnf'

workflow REPRESENT {
    take:
    reps        // channel: [ meta(name, tool, features_source), config ], from VALIDATE
    sequences   // value channel: input table (id, sequence, ...)
    manifest    // value channel: Eris manifest, or [] when no structures
    structures  // value channel: list of structure files, or []

    main:
    def ready = reps.branch { meta, _config ->
        encode: meta.tool == 'sylphy-encode'
        embed: meta.tool == 'sylphy-embed'
        roxy: meta.tool == 'roxy'
        eris: meta.tool == 'eris'
    }

    SYLPHY_ENCODE(ready.encode, sequences)
    SYLPHY_EMBED(ready.embed, sequences)
    ROXY_COMPUTE(ready.roxy, sequences)
    KPNF_STAGE_MANIFEST(manifest.filter { m -> m })
    ERIS_FEATURES(ready.eris, KPNF_STAGE_MANIFEST.out, structures)

    def all_matrices = SYLPHY_ENCODE.out.matrix
        .mix(SYLPHY_EMBED.out.matrix, ROXY_COMPUTE.out.matrix, ERIS_FEATURES.out.matrix)
    def all_provenance = SYLPHY_ENCODE.out.provenance
        .mix(SYLPHY_EMBED.out.provenance, ROXY_COMPUTE.out.provenance, ERIS_FEATURES.out.provenance)

    emit:
    matrices = all_matrices       // channel: [ meta, matrix ]
    provenance = all_provenance   // channel: sidecar of each matrix
}
