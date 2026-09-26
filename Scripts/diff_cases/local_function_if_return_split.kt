// A local (statement-position) function whose body has a braceless early
// return (`if (cond) return x`) followed by another statement used to lose
// that trailing statement entirely: `BuildASTPhase.splitTokensIntoStatements`
// tracked `<`/`>` as generic-argument brackets even when they were really a
// comparison operator, so the unmatched `<` in `x < 0` permanently disabled
// top-level statement-boundary detection for the rest of the body, merging
// "return 0" and "return x * 3" into one statement (only the first ever ran).
fun localTest(x: Int): Int {
    if (x < 0) return 0
    return x * 3
}

fun main() {
    println(localTest(2))
    println(localTest(-2))
}
