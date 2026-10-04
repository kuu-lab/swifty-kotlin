// KUU-965: Package-qualified kotlin.comparisons.minOf/maxOf calls fold
// through the same inline lowering as the unqualified spelling instead of
// emitting a reference to the source-backed (never-linked) symbol.
fun main() {
    println(kotlin.comparisons.minOf(2L, 3L))
    println(kotlin.comparisons.maxOf(2L, 3L))
    println(kotlin.comparisons.minOf(5, 1))
    println(kotlin.comparisons.maxOf(5, 1))
    println(kotlin.comparisons.minOf(2L, 3L, 1L))
    println(kotlin.comparisons.minOf(4L, 2L, 6L, 1L))
    println(kotlin.comparisons.minOf(2.5, 1.5))
    println(kotlin.comparisons.maxOf(2.5f, 1.5f))
    println(kotlin.comparisons.minOf("abc", "abd"))
    println(kotlin.comparisons.maxOf("abc", "abd"))
    println(kotlin.comparisons.minOf(3, 2, 1, comparator = kotlin.comparisons.naturalOrder<Int>()))
    println(kotlin.comparisons.maxOf(3, 2, 1, comparator = kotlin.comparisons.naturalOrder<Int>()))
}
