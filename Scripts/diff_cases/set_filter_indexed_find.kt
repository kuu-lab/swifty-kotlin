fun probe(values: Iterable<Int>) {
    val offset = 1
    val threshold = 2
    println(values.filterIndexed { i, v -> v > i + offset })
    println(values.find { it >= threshold })
    println(values.find { it > 9 })
}

fun main() {
    println(setOf(1, 2, 3).filterIndexed { i, v -> v > i })
    println(setOf(1, 2, 3).find { it > 1 })
    val values = setOf(3, 1, 2)
    println(values.filterIndexed { i, _ -> i % 2 == 0 })
    println(values.find { it < 3 })
    println(emptySet<Int>().filterIndexed { _, _ -> true })
    println(emptySet<Int>().find { true })
    probe(values)
    probe(mutableSetOf(3, 1, 2))
    val collection: Collection<Int> = values
    println(collection.filterIndexed { i, v -> i < v })
    println(collection.find { it == 2 })
    println(mapOf(3 to "c", 1 to "a", 2 to "b").keys.filterIndexed { i, _ -> i == 1 })
    println(mapOf(3 to "c", 1 to "a", 2 to "b").keys.find { it < 3 })
    val predicate: (Int) -> Boolean = { it > 1 }
    val indexedPredicate: (Int, Int) -> Boolean = { i, v -> i < v }
    println(values.find(predicate))
    println(values.filterIndexed(indexedPredicate))
    // Adjacent Iterable extensions must continue to resolve on Set receivers.
    println(values.filter { it > 1 })
    println(values.filterNot { it > 1 })
    println(values.findLast { it > 1 })
    println(values.mapIndexed { i, v -> i + v })
    println(values.mapNotNull { if (it > 1) it else null })
    println(values.flatMap { listOf(it) })
    println(values.firstOrNull { it > 1 })
    println(values.lastOrNull { it > 1 })
    println(listOf(3, 1, 2).filterIndexed { i, v -> i < v })
    println(listOf(3, 1, 2).find { it > 1 })
    println(sequenceOf(3, 1, 2).filterIndexed { i, v -> i < v }.toList())
    println(sequenceOf(3, 1, 2).find { it > 1 })
}
