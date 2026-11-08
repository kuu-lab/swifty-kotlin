fun main() {
    // KUU-4392: argument-less destination factories must infer their type
    // arguments from the enclosing `C : MutableCollection<in T>` /
    // `M : MutableMap<in K, in V>` bound like kotlinc.
    println(listOf(1, null, 3).filterNotNullTo(mutableListOf()))
    println(listOf(1, 2, 3).filterNotNullTo(mutableListOf()))
    println(listOf(1, null, 3).filterNotNullTo(mutableSetOf()))
    println(listOf(1, null, 3).filterNotNullTo(ArrayDeque()))
    val nullable: List<Int?> = listOf(4, null, 6)
    println(nullable.filterNotNullTo(mutableListOf()))
    println(sequenceOf(1, null, 2).filterNotNullTo(mutableListOf()).toList())

    val map = mapOf(1 to "a", 2 to "b", 3 to "c")
    println(map.filterTo(mutableMapOf()) { it.key > 1 })
    println(map.filterNotTo(mutableMapOf()) { it.key > 1 })

    println(listOf(1, 2).mapTo(mutableListOf()) { it })
    println(listOf(1, 2).filterTo(mutableListOf()) { true })
    println(listOf(1, 2).flatMapTo(mutableListOf()) { listOf(it) })
    println(listOf("a", "b").associateTo(mutableMapOf()) { it to it.length })
}
