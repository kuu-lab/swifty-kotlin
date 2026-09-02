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

fun main() {
    val first: Set<Int> = setOf(3, 1, 2, 2)
    val second: Set<Int> = setOf(2, 3, 1)
    val asCollection: Collection<Int> = first

    println(first.size)
    println(first.containsAll(listOf(1, 2, 3)))
    println(first == second)
    println(first.hashCode() == second.hashCode())
    println(asCollection.contains(2))
    println(asCollection.size)

    for (element in first) print("$element ")
    println()

    val custom = ProbeSet(listOf(8, 7, 8))
    println(custom.size)
    println(custom.contains(8))
    println(custom.iterator().hasNext())
    var customTotal = 0
    for (element in custom) customTotal += element
    println(customTotal)
}
