private class AnyAscendingComparator : Comparator<Any> {
    override fun compare(a: Any, b: Any): Int {
        return (a as Int) - (b as Int)
    }
}

fun sequenceSortedWithComparator(
    values: Sequence<Int>,
    comparator: Comparator<in Int>,
): Sequence<Int> {
    return values.sortedWith(comparator)
}

fun sequenceSortedWithSam(values: Sequence<Int>): Sequence<Int> {
    return values.sortedWith { a, b -> a - b }
}

fun sequenceSortedWithAnyComparator(values: Sequence<Int>): Sequence<Int> {
    val comparator: Comparator<Any> = AnyAscendingComparator()
    return values.sortedWith(comparator)
}
