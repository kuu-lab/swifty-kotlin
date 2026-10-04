private class IntSetIterator(private val items: ArrayList<Int>) : MutableIterator<Int> {
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

private class IntSet : AbstractMutableSet<Int>() {
    private val items = ArrayList<Int>()

    override val size: Int
        get() = items.size

    override fun iterator(): MutableIterator<Int> = IntSetIterator(items)

    override fun contains(element: Int): Boolean = items.contains(element)

    override fun isEmpty(): Boolean = items.isEmpty()

    override fun add(element: Int): Boolean {
        if (items.contains(element)) return false
        items.add(element)
        return true
    }

    override fun addAll(elements: Collection<Int>): Boolean {
        var changed = false
        for (element in elements) {
            if (add(element)) changed = true
        }
        return changed
    }

    override fun remove(element: Int): Boolean = items.remove(element)

    override fun removeAll(elements: Collection<Int>): Boolean {
        var changed = false
        for (element in elements) {
            while (remove(element)) changed = true
        }
        return changed
    }

    override fun retainAll(elements: Collection<Int>): Boolean {
        var changed = false
        var index = 0
        while (index < items.size) {
            val element = items[index]
            if (!elements.contains(element)) {
                items.remove(element)
                changed = true
            } else {
                index += 1
            }
        }
        return changed
    }

    override fun clear() {
        items.clear()
    }
}

private fun asSet(values: Set<Int>): Set<Int> = values
private fun asMutableSet(values: MutableSet<Int>): MutableSet<Int> = values

private fun retainsSetView(values: IntSet): Boolean {
    val readonly: Set<Int> = asSet(values)
    val mutable: MutableSet<Int> = asMutableSet(values)
    return readonly === values && mutable === values
}

fun main() {
    val values = IntSet()
    println(values.add(1))
    println(values.add(1))
    println(values.add(2))
    println(values.contains(2))
    println(values.remove(1))
    println(values.remove(1))
    println(values.addAll(listOf(1, 2, 3, 4)))
    println(values.retainAll(listOf(2, 4, 8)))
    println(values.removeAll(listOf(4, 9)))
    println(values.size)
    values.clear()
    println(values.isEmpty())
    println(retainsSetView(values))

    val left = IntSet()
    left.addAll(listOf(1, 2, 2, 3))
    val right = IntSet()
    right.addAll(listOf(3, 1, 2))
    println(left == right)
    println(left.hashCode() == right.hashCode())
    println(left == asSet(right))
}
