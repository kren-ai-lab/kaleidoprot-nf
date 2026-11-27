// Parameter helpers for main.nf: checks beyond the schema, comparison pairs, inline configs and structure files.

// Pairs of representation names to compare: the given [x, y] pairs, or every pair when unset.
def comparisonPairs(p) {
    if (p.comparisons != null) {
        return p.comparisons
    }
    def names = p.representations.collect { r -> r.name }
    def pairs = []
    names.eachWithIndex { x, i -> names.drop(i + 1).each { y -> pairs << [x, y] } }
    return pairs
}

// Checks nextflow_schema.json cannot express (run after validateParameters): input rows, uniqueness and
// cross-references between representations, comparisons and compositions.
def checkParams(p) {
    def errors = []
    if (p.input ==~ /(?i).*\.(csv|tsv|txt)$/) {
        def lines = file(p.input).withReader { r -> [r.readLine(), r.readLine()] }.findAll { l -> l?.trim() }
        if (lines.size() < 2) {
            errors << "--input ${p.input} has ${lines ? 'a header but no rows' : 'no content'}"
        }
    }
    def names = p.representations.collect { r -> r.name }
    names.findAll { n -> names.count(n) > 1 }.unique().each { n ->
        errors << "representations: duplicated name '${n}'"
    }
    if (!p.structures && p.representations.any { r -> r.tool == 'eris' }) {
        errors << 'Eris representations need --structures (manifest with id,path[,chain,model])'
    }
    comparisonPairs(p).each { pair ->
        if (pair[0] == pair[1] || !(pair[0] in names) || !(pair[1] in names)) {
            errors << "comparisons: ${pair} must name two different representations"
        }
    }
    def comp_names = []
    (p.compositions ?: []).eachWithIndex { c, i ->
        def where = "compositions[${i}]"
        if (c.name in names || c.name in comp_names) {
            errors << "${where}: name '${c.name}' must be unique and differ from representation names"
        }
        comp_names << c.name
        def used = []
        c.blocks.eachWithIndex { b, j ->
            if (!(b.representation in names)) {
                errors << "${where}.blocks[${j}]: unknown representation '${b.representation}'"
            }
            if (b.representation in used) {
                errors << "${where}.blocks[${j}]: '${b.representation}' used twice in one composition"
            }
            used << b.representation
        }
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

// Files listed in an Eris manifest; relative paths resolve against the manifest.
def structureFiles(manifest) {
    manifest.splitCsv(header: true).collect { row ->
        def p = row.path.toString()
        p.startsWith('/') ? file(p, checkIfExists: true) : file(manifest.parent.resolve(p).toString(), checkIfExists: true)
    }
}
