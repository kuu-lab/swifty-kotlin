fun <K, V> removeFromSequence(map: Map<out K, V>, keys: Sequence<K>): Map<K, V> = map - keys

fun <K, V> removeFromArray(map: Map<out K, V>, keys: Array<out K>): Map<K, V> = map - keys

fun main() {
    val map: Map<String?, Int?> = linkedMapOf("a" to 1, null to null, "b" to 2)
    val sequenceResult = removeFromSequence(map, sequenceOf("b", "missing", "b"))
    val arrayResult = removeFromArray(map, arrayOf("a", "missing", "a"))
    val iterableResult = map - listOf(null)
    val keyResult = map - "b"

    println(sequenceResult)
    println(arrayResult)
    println(iterableResult)
    println(keyResult)
}
