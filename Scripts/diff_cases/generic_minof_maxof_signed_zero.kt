// KUU-637: type-erased Comparable minOf/maxOf must follow Double.compare
// total order (-0.0 < 0.0). Concrete maxOf(-0.0, 0.0) already used
// kk_max_double; generic T : Comparable<T> goes through kk_compare_any.
fun <T : Comparable<T>> maxOf2(a: T, b: T): T = maxOf(a, b)
fun <T : Comparable<T>> minOf2(a: T, b: T): T = minOf(a, b)

fun main() {
    println(maxOf2(-0.0, 0.0))
    println(maxOf2(0.0, -0.0))
    println(minOf2(0.0, -0.0))
    println(minOf2(-0.0, 0.0))
    println(maxOf2(-0.0f, 0.0f))
    println(minOf2(0.0f, -0.0f))
}
