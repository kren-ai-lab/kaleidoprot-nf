// Generate every representation listed in params.representations.
// All configs are validated first; no representation starts until every validate-config passed.

include { SYLPHY_VALIDATE     } from '../modules/sylphy'
include { SYLPHY_ENCODE       } from '../modules/sylphy'
include { SYLPHY_EMBED        } from '../modules/sylphy'
include { ROXY_VALIDATE       } from '../modules/roxy'
include { ROXY_COMPUTE        } from '../modules/roxy'
include { ERIS_VALIDATE       } from '../modules/eris'
include { ERIS_FEATURES       } from '../modules/eris'
include { KPNF_STAGE_MANIFEST } from '../modules/kpnf'

workflow REPRESENT {
    take:
    reps       // channel: [ meta(name, tool, features_source), config ]
    sequences  // value channel: input table (id, sequence, ...)
    manifest   // value channel: Eris manifest, or [] when no structures
    structures // value channel: list of structure files, or []

    main:
    def by_tool = reps.branch { meta, _config ->
        sylphy: meta.tool in ['sylphy-encode', 'sylphy-embed']
        roxy: meta.tool == 'roxy'
        eris: meta.tool == 'eris'
    }
    SYLPHY_VALIDATE(by_tool.sylphy)
    ROXY_VALIDATE(by_tool.roxy)
    ERIS_VALIDATE(by_tool.eris)

    def gate = SYLPHY_VALIDATE.out.ok
        .mix(ROXY_VALIDATE.out.ok, ERIS_VALIDATE.out.ok)
        .collect()
        .map { _names -> 'validated' }

    def ready = reps
        .combine(gate)
        .map { meta, config, _gate -> [meta, config] }
        .branch { meta, _config ->
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

    def all_matrices = SYLPHY_ENCODE.out.matrix.mix(SYLPHY_EMBED.out.matrix, ROXY_COMPUTE.out.matrix, ERIS_FEATURES.out.matrix)
    def all_provenance = SYLPHY_ENCODE.out.provenance.mix(SYLPHY_EMBED.out.provenance, ROXY_COMPUTE.out.provenance, ERIS_FEATURES.out.provenance)

    emit:
    matrices   = all_matrices   // channel: [ meta, matrix ]
    provenance = all_provenance // channel: sidecar of each matrix
}
