// KUU-1249: forwarding buildMap must preserve its invariant key type.
fun <T> gather(action: MutableMap<String, T>.() -> Unit): Map<String, T> = buildMap<String, T>(action)

fun <K, V> gatherWithCapacity(action: MutableMap<K, V>.() -> Unit): Map<K, V> = buildMap<K, V>(4, action)

fun main() {
    val first = gather<Int> { put("one", 1) }
    val second = gatherWithCapacity<String, Int> { put("two", 2) }
    println(first.getValue("one"))
    println(second.getValue("two"))
}
