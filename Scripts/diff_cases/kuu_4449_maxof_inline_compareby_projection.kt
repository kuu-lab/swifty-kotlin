// KUU-4449: an inline `compareBy { ... }` argument must take its element type
// from `maxOf`/`minOf`'s `comparator: Comparator<in T>` parameter even though
// the overload set also contains arity-mismatched non-comparator overloads
// (`maxOf(a, b)`, `maxOf(a, b, c)`, vararg forms). Without the enclosing
// candidate's expected type the selector's `T` collapses to `Any`, which
// leaves `it` members unresolved or materializes `Comparator<Any>` and traps
// at runtime.

fun <T> identity(x: T): T = x

fun main() {
    println(maxOf(1, 2, compareBy { -it }))
    println(minOf("a", "bb", compareBy { it.length }))
    println(maxOf(1, 2, 3, compareBy { -it }))
    println(minOf("a", "bb", "ccc", compareBy { it.length }))
    println(maxOf(1, 2, comparator = compareBy { -it }))
    println(maxOf(4, 1, 2, 3, comparator = compareBy { -it }))
    println(listOf(2, 1).sortedWith(compareBy { -it }))
    println(listOf(3, 1, 2).maxWith(compareBy { -it }))
    println(identity(5))
    println(maxOf(1.5, 2.5, compareBy { -it }))
}
