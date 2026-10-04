// KSP-1003: Map.asIterable and Map.asSequence preserve entry typing, order,
// re-iteration, and lazy access to the map's entries.
abstract class CustomMap : Map<String?, Int?>

fun main() {
    val values: Map<String?, Int?> = mapOf(
        "first" to 1,
        null to null,
        "last" to 3
    )

    val iterable = values.asIterable()
    println(iterable.map { "${it.key ?: "<null>"}=${it.value ?: "<null>"}" }.joinToString("|"))
    println(iterable.map { "${it.key ?: "<null>"}=${it.value ?: "<null>"}" }.joinToString("|"))
    println(emptyMap<String?, Int?>().asIterable().map { "${it.key ?: "<null>"}=${it.value ?: "<null>"}" }.joinToString("|"))

    val mutable: MutableMap<String?, Int?> = mutableMapOf("before" to 1)
    val sequence = mutable.asSequence()
    mutable[null] = null
    println(sequence.map { "${it.key ?: "<null>"}=${it.value ?: "<null>"}" }.toList().joinToString("|"))
    mutable["after"] = 3
    println(sequence.map { "${it.key ?: "<null>"}=${it.value ?: "<null>"}" }.toList().joinToString("|"))
}
