class OverrideList : AbstractList<Int>() {
    override val size: Int get() = 1
    override fun get(index: Int): Int = 7
    override fun indexOf(element: Int): Int = 101
    override fun lastIndexOf(element: Int): Int = 202
    override fun subList(fromIndex: Int, toIndex: Int): List<Int> = listOf(303)
}

class ViewList<T>(private val backing: MutableList<T>) : AbstractList<T>() {
    override val size: Int get() = backing.size
    override fun get(index: Int): T = backing[index]
}

fun <L : List<Int>> boundedIndex(list: L): Int = list.indexOf(7)
fun <L : List<Int>> boundedLastIndex(list: L): Int = list.lastIndexOf(7)
fun <L : List<Int>> boundedSubList(list: L): Int = list.subList(0, 1)[0]

fun main() {
    val abstract: AbstractList<Int> = OverrideList()
    val list: List<Int> = abstract
    println(abstract.indexOf(7))
    println(abstract.lastIndexOf(7))
    println(abstract.subList(0, 1)[0])
    println(list.indexOf(7))
    println(list.lastIndexOf(7))
    println(list.subList(0, 1)[0])
    println(boundedIndex(list))
    println(boundedLastIndex(list))
    println(boundedSubList(list))

    val backing = mutableListOf<Int?>(1, null, 1, 3)
    val values: AbstractList<Int?> = ViewList(backing)
    val widened: List<Int?> = values
    println(values.indexOf(1))
    println(values.lastIndexOf(1))
    println(widened.indexOf(null))
    println(widened.lastIndexOf(null))
    println(widened.indexOf(9))
    println(widened.lastIndexOf(9))
    println(values.equals(listOf(1, null, 1, 3)))
    println(values.equals(listOf(3, null, 1, 1)))
    println(values.equals(listOf(1)))
    println(values.equals(setOf(1, null, 3)))
    println(values.equals(null))
    println(values.hashCode())
    val empty: AbstractList<Int?> = ViewList(mutableListOf<Int?>())
    println(empty.indexOf(null))
    println(empty.lastIndexOf(null))
    println(empty.hashCode())
    println(empty.equals(emptyList<Int?>()))
    println(empty.subList(0, 0).size)

    val iterator = empty.iterator()
    println(iterator.hasNext())
    try { iterator.next() } catch (e: NoSuchElementException) { println("iterator-end") }
    val cursor = values.listIterator()
    println(cursor.nextIndex())
    println(cursor.previousIndex())
    println(cursor.hasPrevious())
    try { cursor.previous() } catch (e: NoSuchElementException) { println("iterator-start") }
    println(cursor.next())
    println(cursor.previous())
    val end = values.listIterator(values.size)
    println(end.hasNext())
    println(end.hasPrevious())
    println(end.nextIndex())
    println(end.previousIndex())
    try { end.next() } catch (e: NoSuchElementException) { println("list-iterator-end") }
    println(end.previous())
    try { values.listIterator(-1) } catch (e: IndexOutOfBoundsException) { println("iterator-negative") }
    try { values.listIterator(5) } catch (e: IndexOutOfBoundsException) { println("iterator-past-end") }
    try { values.subList(-1, 1) } catch (e: IndexOutOfBoundsException) { println("sub-negative") }
    try { widened.subList(0, 5) } catch (e: IndexOutOfBoundsException) { println("sub-past-end") }
    try { widened.subList(2, 1) } catch (e: IllegalArgumentException) { println("sub-reversed") }

    val view = widened.subList(1, 4)
    val nested = view.subList(1, 3)
    println(view.size)
    println(view[0])
    println(nested[0])
    backing[1] = 42
    backing[2] = 99
    println(view[0])
    println(view[1])
    println(nested[0])
    println(nested[1])
    try { view[-1] } catch (e: IndexOutOfBoundsException) { println("view-negative") }
    try { view[3] } catch (e: IndexOutOfBoundsException) { println("view-past-end") }
    println(widened.subList(4, 4).size)
}
