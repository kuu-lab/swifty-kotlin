class TrackedMutableSet : MutableSet<Int> {
    val backing = mutableSetOf(1, 2, 3)
    var calls = ""
    override val size: Int get() = backing.size
    override fun isEmpty(): Boolean = backing.isEmpty()
    override fun contains(element: Int): Boolean = backing.contains(element)
    override fun containsAll(elements: Collection<Int>): Boolean = backing.containsAll(elements)
    override fun iterator(): MutableIterator<Int> = backing.iterator()
    override fun add(element: Int): Boolean = backing.add(element)
    override fun addAll(elements: Collection<Int>): Boolean = backing.addAll(elements)
    override fun clear() { backing.clear() }
    override fun remove(element: Int): Boolean = backing.remove(element)
    override fun removeAll(elements: Collection<Int>): Boolean {
        calls += "R"
        if (elements.contains(99)) throw IllegalStateException("removeAll-override")
        return backing.removeAll(elements)
    }
    override fun retainAll(elements: Collection<Int>): Boolean {
        calls += "T"
        if (elements.contains(99)) throw IllegalStateException("retainAll-override")
        return backing.retainAll(elements)
    }
}

fun exercise(set: MutableSet<Int>) {
    println(set.removeAll(listOf(2, 2, 7)))
    println(set.removeAll(listOf(2)))
    println(set.removeAll(emptyList<Int>()))
    println(set.contains(1))
    println(set.contains(2))
    println(set.contains(3))
    println(set.size)
    println(set.retainAll(listOf(3, 3, 7)))
    println(set.retainAll(listOf(3)))
    println(set.contains(1))
    println(set.contains(3))
    println(set.size)
    try { set.removeAll(listOf(99)); println("removeAll-bypassed") }
    catch (e: IllegalStateException) { println(e.message) }
    try { set.retainAll(listOf(99)); println("retainAll-bypassed") }
    catch (e: IllegalStateException) { println(e.message) }
    println(set.size)
    println(set.retainAll(emptyList<Int>()))
    println(set.retainAll(emptyList<Int>()))
    println(set.size)
}

fun main() {
    val source = TrackedMutableSet()
    exercise(source)
    println(source.calls)
    val box = mutableSetOf(1, 2, 3)
    println(box.removeAll(listOf(2, 2)))
    println(box.removeAll(listOf(2)))
    println(box.retainAll(listOf(3)))
    println(box.retainAll(listOf(3)))
    println(box.size)
}
