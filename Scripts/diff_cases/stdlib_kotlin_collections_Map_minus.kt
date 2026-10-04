private fun render(entries: Map<String?, Int?>): String = entries.entries.joinToString("|") { "${it.key}:${it.value}" }

fun main() {
    val map: Map<String?, Int?> = linkedMapOf("a" to 1, null to null, "b" to 2, "c" to 3)
    val oneShotKeys = sequenceOf("b", "b", "missing").constrainOnce()
    val sequenceResult: Map<String?, Int?> = map - oneShotKeys
    val arrayResult: Map<String?, Int?> = map - arrayOf("c", "c", "missing")
    val iterableResult: Map<String?, Int?> = map - listOf(null, "missing")
    val keyResult: Map<String?, Int?> = map - "a"

    println("sequence=${render(sequenceResult)}")
    println("array=${render(arrayResult)}")
    println("iterable=${render(iterableResult)}")
    println("key=${render(keyResult)}")
    println("original=${render(map)}")
    println("fresh=${sequenceResult !== map}")
    println("empty-sequence=${render(map - emptySequence<String?>())}")
    println("empty-array=${render(map - emptyArray<String?>())}")
}
