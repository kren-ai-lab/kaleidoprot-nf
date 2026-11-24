// Check every representation's --config with its tool's validate-config before anything runs.

include { SYLPHY_VALIDATE } from '../modules/sylphy'
include { ROXY_VALIDATE   } from '../modules/roxy'
include { ERIS_VALIDATE   } from '../modules/eris'

workflow VALIDATE {
    take:
    reps // channel: [ meta(name, tool, features_source), config ]

    main:
    def by_tool = reps.branch { meta, _config ->
        sylphy: meta.tool in ['sylphy-encode', 'sylphy-embed']
        roxy: meta.tool == 'roxy'
        eris: meta.tool == 'eris'
    }
    SYLPHY_VALIDATE(by_tool.sylphy)
    ROXY_VALIDATE(by_tool.roxy)
    ERIS_VALIDATE(by_tool.eris)

    // Releases the representations only once every config passed.
    def gate = SYLPHY_VALIDATE.out.ok
        .mix(ROXY_VALIDATE.out.ok, ERIS_VALIDATE.out.ok)
        .collect()
        .map { _names -> 'validated' }
    def validated = reps
        .combine(gate)
        .map { meta, config, _gate -> [meta, config] }

    emit:
    reps = validated // channel: [ meta, config ], emitted after every validate-config passed
}
