class ThrowingCollection : MutableCollection<Int> {
    val failure = IllegalStateException("override")
    override val size: Int get() = 0
    override fun isEmpty(): Boolean = true
    override fun contains(element: Int): Boolean = false
    override fun containsAll(elements: Collection<Int>): Boolean = elements.isEmpty()
    override fun iterator(): MutableIterator<Int> = mutableListOf<Int>().iterator()
    override fun add(element: Int): Boolean { throw failure }
    override fun addAll(elements: Collection<Int>): Boolean { throw failure }
    override fun remove(element: Int): Boolean { throw failure }
    override fun removeAll(elements: Collection<Int>): Boolean { throw failure }
    override fun retainAll(elements: Collection<Int>): Boolean { throw failure }
    override fun clear() { throw failure }
}

fun main() {
    val concrete = ThrowingCollection()
    val collection: MutableCollection<Int> = concrete
    try { collection.remove(1); println("missed-remove") }
    catch (e: IllegalArgumentException) { println("wrong-type") }
    catch (e: IllegalStateException) { println("remove:" + (e === concrete.failure)) }
    try { collection.clear(); println("missed-clear") }
    catch (e: IllegalStateException) { println("clear:" + e.message) }
    try { collection.add(1); println("missed-add") }
    catch (e: IllegalStateException) { println("add:" + e.message) }
    try { collection.addAll(emptyList<Int>()); println("missed-addAll") }
    catch (e: IllegalStateException) { println("addAll:" + e.message) }
    try { collection.removeAll(emptyList<Int>()); println("missed-removeAll") }
    catch (e: IllegalStateException) { println("removeAll:" + e.message) }
    try {
        try { collection.retainAll(emptyList<Int>()) }
        catch (e: IllegalStateException) { throw e }
    } catch (e: IllegalStateException) { println("retainAll:" + (e === concrete.failure)) }
    println("continued")
}
