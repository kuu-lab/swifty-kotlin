// KUU-566: MutableMap.entries predicate mutations must retain MutableEntry member access.

fun main() {
    val retained = mutableMapOf(1 to "a", 2 to "b")
    retained.entries.retainAll { it.key == 2 }
    println(retained)

    val removed = mutableMapOf(1 to "a", 2 to "b")
    removed.entries.removeAll { it.value == "a" }
    println(removed)
}
