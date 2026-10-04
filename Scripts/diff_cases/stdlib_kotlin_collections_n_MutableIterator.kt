// KSP-943: lock the source-backed MutableIterator declaration and its remove()
// member through custom and MutableIterable paths.

package diff

class BagIterator(private val items: ArrayList<Int>) : MutableIterator<Int> {
    private var index = 0

    override fun hasNext(): Boolean = index < items.size

    override fun next(): Int {
        val value = items[index]
        index += 1
        return value
    }

    override fun remove() {
        index -= 1
        items.removeAt(index)
    }
}

class Bag(private val values: ArrayList<Int>) : MutableIterable<Int> {
    override fun iterator(): MutableIterator<Int> = BagIterator(values)
}

fun removeFirst(iterator: MutableIterator<Int>) {
    iterator.next()
    iterator.remove()
}

fun main() {
    val values = ArrayList<Int>()
    values.add(1)
    values.add(2)
    values.add(3)

    val bag = Bag(values)
    removeFirst(bag.iterator())
    println(values)

    // List/set iterator removal uses a separate collection iterator bridge.
}
