// KUU-4130: Iterable/Sequence.toCollection must accept a source-defined
// MutableCollection destination via its `add` member, not just runtime boxes.

class MyList<E> : AbstractMutableList<E>() {
    private val items = mutableListOf<E>()
    override val size: Int get() = items.size
    override fun get(index: Int): E = items[index]
    override fun add(index: Int, element: E) { items.add(index, element) }
    override fun removeAt(index: Int): E = items.removeAt(index)
    override fun set(index: Int, element: E): E = items.set(index, element)
    override fun toString(): String = items.toString()
}

class Bag<E> : MutableCollection<E> {
    private val items = mutableListOf<E>()
    var addCalls = 0
    override val size: Int get() = items.size
    override fun isEmpty(): Boolean = items.isEmpty()
    override fun contains(element: E): Boolean = items.contains(element)
    override fun containsAll(elements: Collection<E>): Boolean = items.containsAll(elements)
    override fun iterator(): MutableIterator<E> = items.iterator()
    override fun add(element: E): Boolean { addCalls++; return items.add(element) }
    override fun remove(element: E): Boolean = items.remove(element)
    override fun addAll(elements: Collection<E>): Boolean = items.addAll(elements)
    override fun removeAll(elements: Collection<E>): Boolean = items.removeAll(elements)
    override fun retainAll(elements: Collection<E>): Boolean = items.retainAll(elements)
    override fun clear() = items.clear()
    override fun toString(): String = items.toString()
}

class BagFromAbstract<E> : AbstractMutableCollection<E>() {
    private val items = mutableListOf<E>()
    override val size: Int get() = items.size
    override fun iterator(): MutableIterator<E> = items.iterator()
    override fun add(element: E): Boolean = items.add(element)
    override fun toString(): String = items.toString()
}

fun main() {
    // The unannotated `MyList()` form additionally requires the KUU-4100
    // inference fix; the explicit-argument form exercises the same runtime path.
    println(listOf(1, 2).toCollection(MyList<Int>()))

    val typed: MyList<Int> = listOf(3, 4).toCollection(MyList<Int>())
    println(typed)

    val bag = Bag<Int>()
    val bagResult = listOf(5, 6, 7).toCollection(bag)
    println(bag)
    println(bag.addCalls)
    println(bagResult === bag)

    val seqBag = Bag<String>()
    sequenceOf("a", "b").toCollection(seqBag)
    println(seqBag)
    println(seqBag.addCalls)

    val amc = BagFromAbstract<Int>()
    listOf(8, 9).toCollection(amc)
    println(amc)

    // Known runtime destinations keep the existing fast path.
    println(listOf(1, 2).toCollection(mutableListOf<Int>()))
    println(listOf(1, 2, 2).toCollection(mutableSetOf<Int>()))
    println(listOf(3, 4).toCollection(ArrayDeque<Int>()))
}
