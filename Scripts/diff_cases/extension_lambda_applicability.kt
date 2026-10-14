// KUU-2149: inapplicable List overloads must not hide Iterable extensions.
package fixture

fun <S, T : S> Iterable<T>.aggregate(operation: (S, T) -> S): S = iterator().next()
fun List<Int>.aggregate(marker: String): String = marker

fun result(values: List<Int>): Int =
    values.aggregate<Int, Int> { acc, item -> acc + item }

// Isolate lambda-shape coverage from dependent accumulator inference (KUU-2155).
fun Iterable<Int>.aggregateTyped(operation: (Int, Int) -> Int): Int = operation(iterator().next(), 0)
fun List<Int>.aggregateTyped(marker: String): String = marker

fun Iterable<Int>.specific(operation: (Int, Int) -> Int): Int = operation(1, 2)
fun List<Int>.specific(operation: (Int, Int) -> Int): Int = operation(3, 4)

fun List<Int>.scoped(operation: (Int, Int) -> Int): Int = operation(1, 2)
fun near(values: List<Int>): Int {
    fun Iterable<Int>.scoped(operation: (Int, Int) -> Int): Int = operation(3, 4)
    return values.scoped { acc, item -> acc + item }
}

fun <S, T : S> Iterable<T>.fallback(operation: (S, T) -> S): S = iterator().next()
fun outer(values: List<Int>): Int {
    fun List<Int>.fallback(marker: String): String = marker
    return values.fallback<Int, Int> { acc, item -> acc + item }
}

fun main() {
    val values = listOf(7, 8)
    println(result(values))
    println(values.aggregateTyped { acc, item -> acc + item })
    println(values.aggregateTyped(operation = { acc, item -> acc + item }))
    println(values.aggregate("marker"))
    println(values.specific { acc, item -> acc + item })
    println(near(values))
    println(outer(values))
}
