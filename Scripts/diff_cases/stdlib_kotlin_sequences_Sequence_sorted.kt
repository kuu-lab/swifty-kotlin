private class AnyAscendingComparator : Comparator<Any> {
    override fun compare(a: Any, b: Any): Int {
        return (a as Int) - (b as Int)
    }
}

private class ThrowingComparator : Comparator<Int> {
    override fun compare(a: Int, b: Int): Int {
        throw IllegalStateException("compare failed")
    }
}

fun main() {
    val comparator: Comparator<Any> = AnyAscendingComparator()
    val values = sequence {
        println("source")
        yield(3)
        yield(1)
        yield(2)
        yield(1)
    }
    val sorted = values.sortedWith(comparator)
    println("created")
    println(sorted.toList())
    println(emptySequence<Int>().sortedWith(comparator).toList())
    println(sequenceOf(1, 1).sortedWith(comparator).toList())
    try {
        sequenceOf(2, 1).sortedWith(ThrowingComparator()).toList()
        println("unexpected")
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
