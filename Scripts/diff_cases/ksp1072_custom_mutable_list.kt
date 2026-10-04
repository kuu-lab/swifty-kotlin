@file:Suppress("DEPRECATION_ERROR")

class TrackedMutableList : AbstractMutableList<Int>() {
    val backing = mutableListOf(1, 2, 3)
    var calls = ""
    override val size: Int get() = backing.size
    override fun get(index: Int): Int = backing[index]
    override fun set(index: Int, element: Int): Int { calls += "s"; return backing.set(index, element) }
    override fun add(element: Int): Boolean { calls += "a"; return backing.add(element) }
    override fun add(index: Int, element: Int) { calls += "i"; backing.add(index, element) }
    override fun addAll(elements: Collection<Int>): Boolean { calls += "A"; return backing.addAll(elements) }
    override fun addAll(index: Int, elements: Collection<Int>): Boolean { calls += "B"; return backing.addAll(index, elements) }
    override fun removeAt(index: Int): Int {
        calls += "d"
        if (index == 99) throw IllegalStateException("removeAt-override")
        return backing.removeAt(index)
    }
    override fun remove(element: Int): Boolean { calls += "r"; return backing.remove(element) }
    override fun clear() { calls += "c"; backing.clear() }
    override fun removeAll(elements: Collection<Int>): Boolean { calls += "R"; return backing.removeAll(elements) }
    override fun retainAll(elements: Collection<Int>): Boolean { calls += "T"; return backing.retainAll(elements) }
    override fun iterator(): MutableIterator<Int> { calls += "j"; return backing.iterator() }
    override fun listIterator(): MutableListIterator<Int> { calls += "l"; return backing.listIterator() }
    override fun listIterator(index: Int): MutableListIterator<Int> { calls += "L"; return backing.listIterator(index) }
    override fun subList(fromIndex: Int, toIndex: Int): MutableList<Int> { calls += "u"; return backing.subList(fromIndex, toIndex) }
}

fun main() {
    val concrete = TrackedMutableList()
    val list: MutableList<Int> = concrete
    println(list.set(0, 10))
    println(list.add(4))
    list.add(1, 9)
    println(list.addAll(listOf(5, 6)))
    println(list.addAll(emptyList<Int>()))
    println(list.addAll(2, listOf(7, 8)))
    println(list.addAll(0, emptyList<Int>()))
    println(list.removeAt(1))
    println(list.remove(3))
    println(list.remove(99))
    println(list.removeAll(listOf(2, 7)))
    println(list.removeAll(listOf(2, 7)))
    println(list.retainAll(listOf(10, 8, 5, 6)))
    println(list.retainAll(listOf(10, 8, 5, 6)))
    println(concrete.backing)
    val iterator = list.iterator()
    println(iterator.next())
    iterator.remove()
    val fromStart = list.listIterator()
    println(fromStart.next())
    fromStart.set(80)
    val fromIndex = list.listIterator(1)
    println(fromIndex.next())
    fromIndex.add(55)
    val sub = list.subList(1, 3)
    sub[0] = 50
    println(concrete.backing)
    try { list.add(-1, 0) } catch (e: IndexOutOfBoundsException) { println("addAt-oob") }
    try { list.addAll(-1, listOf(0)) } catch (e: IndexOutOfBoundsException) { println("addAllAt-oob") }
    try { list.removeAt(99) } catch (e: IllegalStateException) { println(e.message) }
    println(list.remove(index = 2))
    list.clear()
    println(concrete.backing)
    println(concrete.calls)
    val predicates = mutableListOf(80, 50, 55, 6)
    println(predicates.removeAll { it == 50 })
    println(predicates.retainAll { it == 80 })
    println(predicates)
    val arrayList = ArrayList<Int>()
    arrayList.addAll(listOf(1, 2, 2))
    println(arrayList.remove(2))
    println(arrayList.remove(99))
    println(arrayList)
}
