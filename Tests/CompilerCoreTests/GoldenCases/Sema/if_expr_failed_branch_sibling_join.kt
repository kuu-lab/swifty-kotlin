// KUU-4481: a generic call branch whose type arguments stay unsolved
// (`listOf()` → `List<out Nothing>` + SEMA-INFER) is re-solved against the
// sibling branch type. When the sibling nominal is unsatisfiable for the
// call's declared return (`listOf()` can never be `MutableList<Int>`), the
// join of the first-pass type with the sibling provides the common nominal
// (`List<Int>`), matching kotlinc's shared constraint system.
package golden.sema

fun listOrNull(p: Int): List<Int>? = if (p > 0) listOf(p) else null

abstract class FS {
    abstract fun listOrNull(path: String): List<String>?

    fun children(path: String, follow: Boolean): List<String> {
        val children = if (follow) {
            listOrNull(path) ?: listOf()
        } else {
            listOf()
        }
        return children
    }
}

fun probe(t: Boolean) {
    val a = if (t) listOrNull(1) else listOf()
    val b = if (t) listOf() else listOrNull(2)
    val c = if (t) listOf() else mutableListOf(3)
    val d = when {
        t -> mutableListOf(4)
        else -> listOf()
    }
    val e = if (t) emptyList() else setOf(5)
}
