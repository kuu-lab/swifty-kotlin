import java.util.Collections

// KUU-4048: an inline `compareBy { ... }` argument must take its element type
// from `Collections.max`/`min`'s `Comparator<in T>` parameter. Without the
// enclosing call's expected type the selector's `T` collapses to `Any`, which
// materializes `Comparator<Any>` and traps at runtime.

fun <T> myMax(collection: Collection<T>?, comparator: Comparator<in T>?): T =
    collection!!.maxWith(comparator!!)

fun main() {
    println(Collections.max(listOf(1, 2), compareBy { -it }))
    println(Collections.min(listOf(1, 2), compareBy { -it }))
    println(Collections.max(listOf("a", "bb"), compareBy { it.length }))
    println(Collections.max(listOf(1L, 2L), compareBy { -it }))
    println(Collections.max(listOf(1.5, 2.5), compareBy { -it }))
    println(Collections.max(listOf(1, 2), compareByDescending { it }))
    println(Collections.max(listOf(1, 2), naturalOrder()))
    println(Collections.max(listOf<Int?>(1, null), compareBy { it }))
    println(myMax(listOf(1, 2), compareBy { -it }))
    val typed: Comparator<Int> = compareBy { -it }
    println(Collections.max(listOf(1, 2), typed))
    println(listOf(1, 2).maxWith(compareBy { -it }))
    println(listOf(1, 2).sortedWith(compareBy { -it }))
}
