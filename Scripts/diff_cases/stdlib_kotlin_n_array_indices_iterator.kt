fun main() {
    val ints = intArrayOf(3, 1, 2)
    println(ints.indices)
    for (index in ints.indices) print(index)
    println()
    println(ints.lastIndex)

    val strings = arrayOf("x", "y")
    println(strings.indices)
    println(strings.lastIndex)
    for (index in strings.indices) print(strings[index])
    println()
    println(strings.withIndex().last())
    println(strings.iterator().next())

    println(ints.withIndex().last())
    val intIterator = ints.iterator()
    println(intIterator.hasNext())
    println(intIterator.next())

    val longs = longArrayOf(10L, 20L)
    println(longs.indices)
    println(longs.lastIndex)
    println(longs.withIndex().last())
    println(longs.iterator().next())

    ints.sort()
    println(ints.contentToString())

    val sortable = intArrayOf(3, -1, 3, 0)
    sortable.sort()
    println(sortable.contentToString())

    val empty = IntArray(0)
    println(empty.indices)
    println(empty.lastIndex)
    println(empty.iterator().hasNext())
}
