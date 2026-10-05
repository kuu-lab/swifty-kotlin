fun <R> accept(range: R): Boolean where R : ClosedRange<Int>, R : Iterable<Int> = true

fun <T, R> inspect(range: R, value: T): Boolean where T : Comparable<T>, R : ClosedRange<T>, R : Iterable<T> {
    return range.start <= value && value <= range.endInclusive && range.contains(value)
}

fun <R> sumRange(range: R): Int where R : ClosedRange<Int>, R : Iterable<Int> {
    var total = 0
    for (value in range) total += value
    return total
}

fun <T> identity(value: T): T = value
fun choose(value: Int): String = "scalar"
fun <R> choose(value: R): String where R : ClosedRange<Int>, R : Iterable<Int> = "range"

class Acceptor {
    fun <R> accept(range: R): Boolean where R : ClosedRange<Int>, R : Iterable<Int> {
        return range.contains(3)
    }
}

fun main() {
    println(accept(1..10))
    val range = 1..10
    println(accept(range))
    println(accept(range = 1..10))
    println(accept<IntRange>(1..10))
    println(inspect(1..10, 3))
    println(inspect(1L..10L, 3L))
    println(inspect('a'..'z', 'd'))
    println(inspect(1u..10u, 3u))
    println(inspect(1uL..10uL, 3uL))
    println(sumRange(1..10))
    println(sumRange(range))
    println(sumRange(10..1))
    val returned: IntRange = identity(1..3)
    println(returned.contains(2))
    println(choose(1..10))
    println(choose(1))
    println(Acceptor().accept(1..10))
}
