// KUU-4481: an if/when branch whose generic call cannot solve its type
// arguments on its own (`listOf()`/`emptyList()` + SEMA-INFER) is re-solved
// against the sibling branch type; when the sibling nominal is
// unsatisfiable for the call's return (`listOf()` vs `MutableList<Int>`),
// the common nominal supertype (`List<Int>`/`Collection<Int>`) is used —
// matching kotlinc's shared constraint system.

fun listOrNull(p: Int): List<Int>? = if (p > 0) listOf(p) else null

fun main() {
    val a = if (true) listOrNull(1) else listOf()
    println(a?.size)

    val b = if (false) listOf() else listOrNull(2)
    println(b?.size)

    val c = if (true) listOf() else mutableListOf(3)
    println(c.size)

    val d = when {
        false -> mutableListOf(4)
        else -> listOf()
    }
    println(d.size)

    val e = when (true) {
        true -> listOf()
        else -> mutableListOf(5)
    }
    println(e.size)

    val f = if (true) emptyList() else setOf(6)
    println(f.size)
}
