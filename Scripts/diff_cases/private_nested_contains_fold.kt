// KUU-1893: preserve a private nested Set element through both predicate lambdas.
class Solver {
    private data class Range(val start: Long) {
        operator fun contains(n: Long) = n == start
        fun translate(n: Long) = n + 10L
    }

    private val maps = listOf(setOf(Range(3L)))

    fun solve(): Long = maps.fold(3L) { acc, ranges ->
        ranges.firstOrNull { acc in it }?.translate(acc) ?: acc
    }

    fun empty(): Long = listOf(emptySet<Range>()).fold(3L) { acc, ranges ->
        ranges.firstOrNull { acc in it }?.translate(acc) ?: acc
    }

    fun missing(): Long = maps.fold(4L) { acc, ranges ->
        ranges.firstOrNull { acc in it }?.translate(acc) ?: acc
    }

    fun chained(): Long = listOf(setOf(Range(3L)), setOf(Range(13L))).fold(3L) { acc, ranges ->
        ranges.firstOrNull { acc in it }?.translate(acc) ?: acc
    }
}

private data class TopLevelRange(val start: Long) {
    operator fun contains(n: Long) = n == start
    fun translate(n: Long) = n + 10L
}

class TopLevelSolver {
    private val maps = listOf(setOf(TopLevelRange(3L)))

    fun solve(): Long = maps.fold(3L) { acc, ranges ->
        ranges.firstOrNull { acc in it }?.translate(acc) ?: acc
    }
}

fun main() {
    val solver = Solver()
    println(solver.solve())
    println(TopLevelSolver().solve())
    println(solver.empty())
    println(solver.missing())
    println(solver.chained())
}
