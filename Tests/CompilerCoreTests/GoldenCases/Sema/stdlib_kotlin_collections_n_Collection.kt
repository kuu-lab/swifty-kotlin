import kotlin.collections.Collection

fun inspect(values: Collection<Int>, other: Collection<Int>): Boolean {
    val size = values.size
    val empty = values.isEmpty()
    val member = values.contains(2)
    val all = values.containsAll(other)
    val iterator = values.iterator()
    return size >= 0 && (empty || member || all || iterator.hasNext())
}
