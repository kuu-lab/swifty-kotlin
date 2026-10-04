private class AnyAscendingComparator : Comparator<Any> {
    override fun compare(a: Any, b: Any): Int {
        return (a as Int) - (b as Int)
    }
}

fun main() {
    val comparator: Comparator<Any> = AnyAscendingComparator()
    val values = sequenceOf(3, 1, 2, 1)
    val sorted = values.sortedWith(comparator)
    println(sorted.toList())
    println(sequenceOf(3, 1, 2, 1).sortedWith { a, b -> b - a }.toList())
}
