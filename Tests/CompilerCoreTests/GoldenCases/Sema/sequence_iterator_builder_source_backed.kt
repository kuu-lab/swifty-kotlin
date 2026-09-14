fun buildValues(): Sequence<Int> = sequence {
    yield(1)
    yieldAll(listOf(2, 3))
}

fun buildIteratorValues(): Iterator<Int> = iterator {
    yield(4)
}
