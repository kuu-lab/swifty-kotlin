package golden.sema

// A `<`/`>` comparison inside a local function's body used to permanently
// disable top-level statement-boundary detection for the rest of that body
// (BuildASTPhase.splitTokensIntoStatements tracked `<` as a generic-argument
// bracket unconditionally), silently dropping every statement after it.
fun localComparisonStatementSplit(): Int {
    fun inner(x: Int): Int {
        if (x < 0) return 0
        return x * 3
    }
    return inner(2) + inner(-2)
}
