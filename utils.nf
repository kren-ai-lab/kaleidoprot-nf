// Parameter helpers for main.nf: checks that fail before any task runs, comparison pairs and inline configs.

// Pairs of representation names to compare: 'all', or a list of [x, y].
def comparisonPairs(p) {
    def names = p.representations.collect { r -> r.name }
    if (p.comparisons == 'all') {
        def pairs = []
        names.eachWithIndex { x, i -> names.drop(i + 1).each { y -> pairs << [x, y] } }
        return pairs
    }
    return (p.comparisons ?: []).collect { pair -> pair as List }
}

// Fail before any task runs. Tool-level options are checked by each tool's validate-config.
def checkParams(p) {
    def TOOLS = ['sylphy-encode', 'sylphy-embed', 'roxy', 'eris']
    def NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]*$/
    // Every parameter in nextflow.config; anything else is a typo.
    def KNOWN = [
        'input', 'seq_column', 'label_column', 'structures', 'representations', 'compositions', 'comparisons',
        'alignment', 'projection_components', 'comparison_components', 'projection_scaling', 'mantel_permutations',
        'eda_max_columns', 'seed', 'selection', 'outdir', 'publish_dir_mode',
    ]
    def errors = []
    def unknown = p.keySet() - KNOWN
    if (unknown) {
        errors << "unknown parameters: ${unknown.sort().join(', ')} (check the spelling)"
    }
    if (!p.input) {
        errors << "--input is required (table with columns id and ${p.seq_column})"
    }
    if (!(p.representations instanceof List) || !p.representations) {
        errors << 'representations: give a non-empty list (see examples/test/params.yaml)'
        return errors
    }
    def names = []
    p.representations.eachWithIndex { r, i ->
        def where = "representations[${i}]"
        if (!(r instanceof Map)) {
            errors << "${where}: expected a map with name, tool and config"
            return null
        }
        if (!(r.name ==~ NAME_PATTERN) || r.name.contains('__')) {
            errors << "${where}: name '${r.name}' must match ${NAME_PATTERN} and not contain '__'"
        }
        if (r.name in names) {
            errors << "${where}: duplicated name '${r.name}'"
        }
        names << r.name
        if (!(r.tool in TOOLS)) {
            errors << "${where}: tool '${r.tool}' is not one of ${TOOLS.join(', ')}"
        }
        if (!(r.config instanceof Map) && !(r.config instanceof CharSequence && r.config)) {
            errors << "${where}: config is required: the tool's options as a map, or the path to its --config file"
        }
        if (r.tool == 'eris' && !p.structures) {
            errors << "${where}: Eris needs --structures (manifest with id,path[,chain,model])"
        }
    }
    comparisonPairs(p).each { pair ->
        if (pair.size() != 2 || pair[0] == pair[1] || !(pair[0] in names) || !(pair[1] in names)) {
            errors << "comparisons: ${pair} must name two different representations"
        }
    }
    def comp_names = []
    (p.compositions ?: []).eachWithIndex { c, i ->
        def where = "compositions[${i}]"
        if (!(c.name ==~ NAME_PATTERN) || c.name.contains('__') || c.name in names || c.name in comp_names) {
            errors << "${where}: name '${c.name}' must be valid, unique and differ from representation names"
        }
        comp_names << c.name
        if (!(c.blocks instanceof List) || c.blocks.size() < 2) {
            errors << "${where}: blocks needs at least two entries"
            return null
        }
        def used = []
        c.blocks.eachWithIndex { b, j ->
            if (!(b.representation in names)) {
                errors << "${where}.blocks[${j}]: unknown representation '${b.representation}'"
            }
            if (b.representation in used) {
                errors << "${where}.blocks[${j}]: '${b.representation}' used twice in one composition"
            }
            used << b.representation
            if (b.reduce && b.select) {
                errors << "${where}.blocks[${j}]: use either reduce or select, not both"
            }
            if (b.reduce && !(b.reduce instanceof Integer && b.reduce > 0)) {
                errors << "${where}.blocks[${j}]: reduce must be a positive number of PCA components"
            }
        }
        if (c.scaling && !(c.scaling in ['none', 'standard', 'block'])) {
            errors << "${where}: scaling must be none, standard or block"
        }
    }
    if (!(p.comparison_components instanceof Integer && p.comparison_components >= 2)) {
        errors << 'comparison_components must be an integer >= 2 (the figures plot PC1 and PC2)'
    }
    if (!(p.alignment in ['strict', 'partial'])) {
        errors << 'alignment must be strict or partial'
    }
    return errors
}

// An inline config (a map in params) as a file the tool reads with --config. JSON, which the tools read as YAML.
// Rewritten only when its content changes: the task cache keys on the file's mtime, so -resume keeps working.
def inlineConfig(name, config) {
    def f = file("${workflow.workDir}/configs/${name}.json")
    def text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(config)) + '\n'
    if (!f.exists() || f.text != text) {
        f.parent.mkdirs()
        f.text = text
    }
    return f
}
