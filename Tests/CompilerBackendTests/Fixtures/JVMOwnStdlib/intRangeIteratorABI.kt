fun main() {
    val range = kotlin.ranges.IntRange(1, 3)
    val erasedRange: Any = range
    println(erasedRange is MutableIterable<*>)
    val cursor = range.iterator()
    val erasedCursor: Any = cursor
    println(erasedCursor is MutableIterator<*>)
    println(cursor.nextInt())
    println(cursor.next())
    println(cursor.nextInt())
    println(cursor.hasNext())
    try { cursor.nextInt() } catch (e: NoSuchElementException) { println("exhausted") }
    val iterable: Iterable<Int> = range
    for (value in iterable) println(value)
    for (value in range) println(value)
    val empty = kotlin.ranges.IntRange(2, 1).iterator()
    println(empty.hasNext())
    try { empty.next() } catch (e: NoSuchElementException) { println("empty") }
    val edge = kotlin.ranges.IntRange(2147483647, 2147483647).iterator()
    println(edge.nextInt())
    println(edge.hasNext())
    for (value in 1..2) println(value)
}
