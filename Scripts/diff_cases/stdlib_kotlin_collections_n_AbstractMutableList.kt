// KSP-929: AbstractMutableList is source-backed while MutableList's shared
// runtime bridges remain available for concrete runtime lists.

import kotlin.collections.AbstractMutableList

class ProbeIterator(private val storage: ArrayList<Int>) : MutableIterator<Int> {
    private var index = 0

    override fun hasNext(): Boolean = index < storage.size

    override fun next(): Int = storage[index++]

    override fun remove() {
        storage.removeAt(--index)
    }
}

class Probe : AbstractMutableList<Int>() {
    private val storage = arrayListOf(1, 2, 3)

    override val size: Int
        get() = storage.size

    override fun get(index: Int): Int = storage[index]

    override fun set(index: Int, element: Int): Int = storage.set(index, element)

    override fun add(index: Int, element: Int) {
        storage.add(index, element)
    }

    override fun removeAt(index: Int): Int = storage.removeAt(index)

    override fun iterator(): MutableIterator<Int> = ProbeIterator(storage)
}

// Keep interface-typed source calls in a non-executed function: the source
// class hierarchy and member signatures are checked without treating a custom
// object as one of the runtime's built-in list boxes.
fun typedAccess(probe: Probe) {
    val asList: List<Int> = probe
    val asMutable: MutableList<Int> = probe
    asList.size
    asMutable.add(4)
    asMutable.set(0, 9)
    asMutable.remove(2)
    asMutable.clear()
    asMutable.listIterator()
    asList.subList(0, 0)
    asMutable.subList(0, 0)
}

fun main() {
    val probe = Probe()
    probe.add(1, 8)
    println(probe[1])
    println(probe.set(0, 9))
    println(probe.removeAt(2))
    println(probe.size)
    println(probe.iterator().hasNext())

    val values: MutableList<Int> = arrayListOf(1, 2, 3)
    println(values.add(4))
    println(values.set(0, 9))
    println(values.remove(2))
    values.clear()
    println(values.size)
    println(values.listIterator().hasNext())
    println(values.subList(0, 0).size)
    try {
        values.add(99, 1)
        println("no-bounds")
    } catch (e: Exception) {
        println("bounds")
    }
}
