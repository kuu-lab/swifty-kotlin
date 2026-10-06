private class TwoValues : Iterable<Int> {
    override fun iterator(): Iterator<Int> = listOf(3, 5).iterator()
}

fun inspect(values: Iterable<Int>): Int {
    val iterator = values.iterator()
    return if (iterator.hasNext()) iterator.next() else 0
}

fun main() {
    inspect(TwoValues())
}
