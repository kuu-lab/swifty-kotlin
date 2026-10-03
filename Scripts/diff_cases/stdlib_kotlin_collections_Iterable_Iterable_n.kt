// KSP-1061: source-owned Iterable.iterator retains lazy, throwing dispatch.
private var calls = 0

private class TwoValues : Iterable<Int> {
    override fun iterator(): Iterator<Int> {
        calls++
        return listOf(3, 5).iterator()
    }
}

private class ThrowingValues : Iterable<Int> {
    override fun iterator(): Iterator<Int> = throw IllegalStateException("iterator")
}

fun main() {
    val values: Iterable<Int> = TwoValues()
    println(calls)
    val iterator = values.iterator()
    println(calls)
    println(iterator.next())
    println(iterator.next())
    println(iterator.hasNext())
    println(values.toList())
    println(calls)
    val throwing: Iterable<Int> = ThrowingValues()
    try {
        throwing.iterator()
    } catch (exception: IllegalStateException) {
        println(exception.message)
    }
}
