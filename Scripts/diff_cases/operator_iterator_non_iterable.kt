// DIFF_JVM
class Values {
    var iteratorCalls = 0
    operator fun iterator(): Iterator<Int> {
        iteratorCalls += 1
        return listOf(1, 2, 3).iterator()
    }
}

class CountingIterable : Iterable<Int> {
    var iteratorCalls = 0
    override fun iterator(): Iterator<Int> {
        iteratorCalls += 1
        return listOf(4, 5).iterator()
    }
}

fun sum(values: Values): Int {
    var total = 0
    for (value in values) total += value
    return total
}

fun main() {
    val values = Values()
    println(sum(values))
    println(values.iteratorCalls)

    val iterable = CountingIterable()
    var iterableTotal = 0
    for (value in iterable) iterableTotal += value
    println(iterableTotal)
    println(iterable.iteratorCalls)

    var arrayTotal = 0
    for (value in intArrayOf(6, 7, 8)) arrayTotal += value
    println(arrayTotal)
}
