fun main() {
    val list = mutableListOf(1, 2, 3)
    list.addAll(listOf(4, 5))
    println(list)

    list.removeAll(listOf(2, 4))
    println(list)

    list.retainAll(listOf(1, 5))
    println(list)

    // addAll(index, elements): insert-at-index bulk overload.
    val indexed = mutableListOf(1, 2, 3)
    val changed = indexed.addAll(1, listOf(100, 200))
    println(changed)
    println(indexed)

    // addAll(index, emptyList()) must not mutate and must return false.
    val unchangedResult = indexed.addAll(0, emptyList())
    println(unchangedResult)
    println(indexed)
}
