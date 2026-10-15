fun applyInt(op: (Int, Int) -> Int): Int = op(2, 3)
fun intPlus(): (Int, Int) -> Int = Int::plus
fun longTimes(): (Long, Long) -> Long = Long::times
fun product(values: List<Long>): Long = values.reduce(Long::times)
fun iterableProduct(values: Iterable<Long>): Long = values.reduce(Long::times)
fun iterableSum(values: Iterable<Long>): Long = values.reduce(Long::plus)

fun main() {
    val plus: (Int, Int) -> Int = Int::plus
    val times: (Int, Int) -> Int = Int::times
    println(plus(2, 3))
    println(times(2, 3))
    println(applyInt(Int::plus))
    println(applyInt(Int::times))
    println(intPlus()(2, 3))
    println(longTimes()(7L, 6L))
    println(listOf(1, 2, 3).fold(0, Int::plus))
    println(listOf(1, 2, 3).reduce(Int::times))
    println(listOf(1L, 2L, 3L).fold(0L, Long::plus))
    println(listOf(1L, 2L, 3L).reduce(Long::times))
    println(product(listOf(2L, 3L, 4L)))
    println(iterableProduct(listOf(2L, 3L, 4L)))
    println(iterableSum(listOf(2L, 3L, 4L)))
}
