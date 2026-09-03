package golden.sema

class ProbeSet(private val values: List<Int>) : Set<Int> {
    override val size: Int
        get() = values.size

    override fun contains(element: Int): Boolean = values.contains(element)

    override fun containsAll(elements: Collection<Int>): Boolean {
        for (element in elements) {
            if (!contains(element)) return false
        }
        return true
    }

    override fun isEmpty(): Boolean = values.isEmpty()

    override fun iterator(): Iterator<Int> = values.iterator()
}

fun inspect(values: Set<Int>, collection: Collection<Int>): Boolean {
    val iterator = values.iterator()
    return values.contains(1) && values.containsAll(listOf(1)) && collection.contains(1) && iterator.hasNext()
}
