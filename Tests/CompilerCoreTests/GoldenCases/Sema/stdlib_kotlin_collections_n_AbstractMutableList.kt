package golden.sema

import kotlin.collections.AbstractMutableList
import kotlin.collections.List
import kotlin.collections.MutableList

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

fun acceptList(values: List<Int>) = values.size

fun acceptMutableList(values: MutableList<Int>) = values.size

fun probe(values: Probe): Int {
    val asList: List<Int> = values
    val asMutable: MutableList<Int> = values
    asList.subList(0, 0)
    asMutable.listIterator()
    asMutable.subList(0, 0)
    return acceptList(asList) + acceptMutableList(asMutable) + values[0]
}
