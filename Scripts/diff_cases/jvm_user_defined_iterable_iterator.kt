// DIFF_JVM

class Fibs(val n: Int) : Iterable<Int> {
    override fun iterator() = object : IntIterator() {
        var c = 0
        override fun hasNext() = c < n
        override fun nextInt() = c++
    }
}

class DirectIterator : Iterator<Int> {
    private var c = 0
    override fun hasNext() = c < 2
    override fun next() = ++c
}

class DirectListIterator : ListIterator<Int> {
    private var c = 0
    override fun hasNext() = c < 2
    override fun next() = ++c
    override fun hasPrevious() = c > 0
    override fun previous() = --c
    override fun nextIndex() = c
    override fun previousIndex() = c - 1
}

class DirectSequence : Sequence<Int> {
    override fun iterator() = listOf(7, 8).iterator()
}

class DirectMap(private val source: Map<String, Int>) : Map<String, Int> {
    override val entries get() = source.entries
    override val keys get() = source.keys
    override val size get() = source.size
    override val values get() = source.values
    override fun containsKey(key: String) = source.containsKey(key)
    override fun containsValue(value: Int) = source.values.contains(value)
    override fun get(key: String) = source[key]
    override fun isEmpty() = source.isEmpty()
}

class DirectMutableList : MutableList<Int> {
    private val source = arrayListOf(4, 5)
    override val size get() = source.size
    override fun isEmpty() = source.isEmpty()
    override fun contains(element: Int) = source.contains(element)
    override fun containsAll(elements: Collection<Int>) = source.containsAll(elements)
    override fun iterator() = source.iterator()
    override fun get(index: Int) = source.get(index)
    override fun indexOf(element: Int) = source.indexOf(element)
    override fun lastIndexOf(element: Int) = source.lastIndexOf(element)
    override fun listIterator(): MutableListIterator<Int> = source.listIterator()
    override fun listIterator(index: Int): MutableListIterator<Int> = source.listIterator(index)
    override fun subList(fromIndex: Int, toIndex: Int): MutableList<Int> = source.subList(fromIndex, toIndex)
    override fun set(index: Int, element: Int) = source.set(index, element)
    override fun add(element: Int) = source.add(element)
    override fun add(index: Int, element: Int) = source.add(index, element)
    override fun addAll(elements: Collection<Int>) = source.addAll(elements)
    override fun addAll(index: Int, elements: Collection<Int>) = source.addAll(index, elements)
    override fun remove(element: Int) = source.remove(element)
    override fun removeAll(elements: Collection<Int>) = source.removeAll(elements)
    override fun retainAll(elements: Collection<Int>) = source.retainAll(elements)
    override fun clear() = source.clear()
    override fun removeAt(index: Int) = source.removeAt(index)
}

fun main() {
    for (x in Fibs(3)) print(x)
    println()
    val iterable: Iterable<Int> = Fibs(1)
    print(iterable.iterator().next())
    println()
    val iterator: Iterator<Int> = DirectIterator()
    for (x in iterator) print(x)
    println()
    val listIterator: ListIterator<Int> = DirectListIterator()
    print(listIterator.next())
    print(listIterator.hasPrevious())
    print(listIterator.previous())
    println()
    for (x in DirectSequence()) print(x)
    println()
    val map: Map<String, Int> = DirectMap(mapOf("answer" to 42))
    println(map["answer"])
    println(map.keys.contains("answer"))
    println(map.containsValue(42))
    println(map.size)
    val mutableList: MutableList<Int> = DirectMutableList()
    println(mutableList[1])
    mutableList.add(6)
    println(mutableList.size)
}
