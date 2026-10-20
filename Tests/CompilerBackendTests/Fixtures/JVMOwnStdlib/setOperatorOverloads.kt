fun main() {
    val source = setOf(3, 1, 2)
    val duplicate: Set<Int> = source + 1
    println(duplicate); println(duplicate.size)
    val appended: Set<Int> = source.plus(4)
    println(appended)
    val other: Iterable<Int> = listOf(2, 4, 4, 0)
    val bulk: Set<Int> = source + other
    println(bulk)
    val removed: Set<Int> = source - 1
    println(removed)
    val missing: Set<Int> = source.minus(8)
    println(missing)
    val bulkRemoved: Set<Int> = source - listOf(3, 3, 2)
    println(bulkRemoved)
    println(source)
    val empty: Set<Int> = emptySet<Int>() + listOf(2, 2, 1)
    println(empty)
    val nullable = setOf<Int?>(null, 1, 2)
    val withoutNull: Set<Int?> = nullable - null
    println(withoutNull); println(nullable + listOf(null, 3))
    val iterable: Iterable<Int> = source
    val list: List<Int> = iterable + 1
    println(list)
}
