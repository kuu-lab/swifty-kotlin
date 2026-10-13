// KUU-1860: Match Kotlin/JVM MutableMap.putIfAbsent for absent, present, and null mappings.
// Pinned upstream program: https://github.com/DmitryTsyvtsyn/Kotlin-Algorithms-and-Design-Patterns/blob/1f89f062a056e24cc289ffdd0c6e23cadf8df887/src/main/kotlin/structures/Graph.kt

fun main() {
    val values = linkedMapOf<String, String?>("null" to null, "present" to "old")
    println(values.putIfAbsent("new", "first"))
    println(values.putIfAbsent("present", "replacement"))
    println(values.putIfAbsent("null", "filled"))
    println(values.entries.joinToString(",") { "${it.key}=${it.value}" })
}
