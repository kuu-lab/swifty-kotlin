// KSP-1020: source-backed predicate extensions on MutableIterable.

class ProbeIterator(private val values: ArrayList<Int>) : MutableIterator<Int> {
    private var index = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): Int {
        val value = values[index]
        index += 1
        return value
    }

    override fun remove() {
        index -= 1
        values.removeAt(index)
    }
}

class ProbeIterable(private val values: ArrayList<Int>) : MutableIterable<Int> {
    override fun iterator(): MutableIterator<Int> = ProbeIterator(values)
}

fun probe(values: MutableIterable<Int>): Boolean {
    return values.removeAll { it > 0 } || values.retainAll { it == 0 }
}
