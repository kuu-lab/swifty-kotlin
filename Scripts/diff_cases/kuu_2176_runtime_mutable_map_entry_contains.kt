private class EntryProbeSet(
    private val backing: MutableMap.MutableEntry<String, String>
) : AbstractMutableSet<MutableMap.MutableEntry<String, String>>() {
    override val size: Int get() = 1

    override fun iterator(): MutableIterator<MutableMap.MutableEntry<String, String>> =
        mutableListOf(backing).iterator()

    override fun add(element: MutableMap.MutableEntry<String, String>): Boolean = false

    override fun contains(element: MutableMap.MutableEntry<String, String>): Boolean =
        element.key == backing.key && element.value == backing.value
}

fun main() {
    val map = linkedMapOf("a" to "b")
    val rawEntry = map.entries.first()
    val entries: Set<MutableMap.MutableEntry<String, String>> = EntryProbeSet(rawEntry)
    println(entries.contains(rawEntry))
}
