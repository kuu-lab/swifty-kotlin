private fun <K, V> readOnly(entry: MutableMap.MutableEntry<K, V>): Map.Entry<K, V> = entry

private fun show(entry: MutableMap.MutableEntry<String, Int>) {
    println(entry.key)
    println(entry.value)
    val wide: Map.Entry<Any, Any> = readOnly(entry)
    println(wide.key)
    println(wide.value)
    val (key, value) = entry
    println(key)
    println(value)
}

fun main() {
    val map = mutableMapOf("key" to 1)
    val entry: MutableMap.MutableEntry<String, Int> = map.entries.iterator().next()
    show(entry)
    println(entry.setValue(42))
    println(entry.value)
    println(map["key"])
    val nullableMap = mutableMapOf<String?, Int?>(null to null)
    val nullable: MutableMap.MutableEntry<String?, Int?> = nullableMap.entries.iterator().next()
    println(nullable.key)
    println(nullable.value)
    println(nullable.setValue(7))
    println(nullable.value)
    println(nullableMap[null])
}
