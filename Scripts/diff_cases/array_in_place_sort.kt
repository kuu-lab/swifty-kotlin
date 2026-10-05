class ArraySortItem(val key: Int, val order: Int) : Comparable<ArraySortItem> {
    override fun compareTo(other: ArraySortItem): Int = key.compareTo(other.key)
    override fun toString(): String = "$key:$order"
}

fun checkSortBounds(from: Int, to: Int, descending: Boolean) {
    val array = intArrayOf(3, 2, 1)
    try {
        if (descending) array.sortDescending(from, to) else array.sort(from, to)
        println("accepted")
    } catch (e: IndexOutOfBoundsException) {
        println("bounds")
    } catch (e: IllegalArgumentException) {
        println("order")
    }
    println(array.toList())
}

fun main() {
    val a = intArrayOf(3, 1, 2)
    a.sortDescending()
    println(a.toList())
    val b = intArrayOf(3, 1, 2)
    b.sort(1, 3)
    println(b.toList())
    val c = arrayOf("b", "a")
    c.sort()
    println(c.toList())
    val (x, y, z) = intArrayOf(1, 2, 3)
    println("$x$y$z")

    val range = intArrayOf(99, 4, -2, 4, 0, -99)
    val alias = range
    range.sort(toIndex = 5, fromIndex = 1)
    println(alias.toList())
    range.sortDescending(1, 5)
    println(alias.toList())
    range.sort(3, 3)
    range.sortDescending(6, 6)
    range.sort(2, 3)
    println(range.toList())

    val defaultEnd = intArrayOf(9, 3, 2, 1)
    defaultEnd.sort(fromIndex = 1)
    println(defaultEnd.toList())
    val defaultStart = intArrayOf(3, 2, 1, 9)
    defaultStart.sort(toIndex = 3)
    println(defaultStart.toList())
    defaultStart.sort()
    println(defaultStart.toList())

    val empty = intArrayOf()
    empty.sort()
    empty.sort(0, 0)
    empty.sortDescending()
    empty.sortDescending(0, 0)
    println(empty.toList())
    val singleton = intArrayOf(42)
    singleton.sortDescending()
    singleton.sort(0, 1)
    println(singleton.toList())
    val extremes = intArrayOf(Int.MIN_VALUE, 0, Int.MAX_VALUE, -1, 0)
    extremes.sortDescending()
    println(extremes.toList())
    val mergeRange = IntArray(42) { 42 - it }
    mergeRange.sort(1, 41)
    println(mergeRange.toList())
    mergeRange.sortDescending(1, 41)
    println(mergeRange.toList())

    checkSortBounds(2, 1, false)
    checkSortBounds(-1, 2, false)
    checkSortBounds(0, 4, false)
    checkSortBounds(4, 4, false)
    checkSortBounds(-1, -1, false)
    checkSortBounds(2, 1, true)
    checkSortBounds(-1, 2, true)
    checkSortBounds(0, 4, true)

    val projected: Array<out String> = arrayOf("z", "b", "a", "b")
    val projectedAlias = projected
    projected.sort()
    println(projectedAlias.toList())
    val genericInts = arrayOf(3, -1, 2, 2)
    genericInts.sort()
    println(genericInts.toList())
    val emptyGeneric = emptyArray<String>()
    emptyGeneric.sort()
    println(emptyGeneric.toList())
    val one = arrayOf("only")
    one.sort()
    println(one.toList())
    val stable = Array(40) { ArraySortItem(it % 3, it) }
    stable.sort()
    println(stable.toList())
}
