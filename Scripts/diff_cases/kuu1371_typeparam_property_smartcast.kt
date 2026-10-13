// KUU-1371: smart-cast `R & List<*>` on a type-parameter member property must
// still resolve extension member calls such as Collection.isNotEmpty().
class D<R>(val defaultValue: R?)

fun <R> f(d: D<R>): Boolean =
    d.defaultValue != null && (d.defaultValue is List<*> && d.defaultValue.isNotEmpty() || d.defaultValue !is List<*>)

fun main() {
    println(f(D<List<Int>>(listOf(1, 2))))
    println(f(D<List<Int>>(emptyList())))
    println(f(D<Int>(5)))
    println(f(D<Int?>(null)))
}
