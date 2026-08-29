private class OneShotSequence<T>(private val values: List<T>) : Sequence<T> {
    var iteratorCalls: Int = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls++
        check(iteratorCalls == 1) { "sequence iterated more than once" }
        return values.iterator()
    }
}

private class ThrowingSequence : Sequence<Pair<String, Int>> {
    override fun iterator(): Iterator<Pair<String, Int>> {
        error("sequence failure")
    }
}

private fun <K, V> render(map: Map<K, V>): String =
    map.entries.joinToString(",") { "${it.key}=${it.value}" }

fun main() {
    val base: Map<String, Int> = linkedMapOf("a" to 1, "b" to 2)

    val iterableResult = base + listOf("b" to 20, "c" to 3, "b" to 21)
    println("iterable=${render(iterableResult)}")
    println("original=${render(base)}")

    val array: Array<Pair<String, Int>> = arrayOf("b" to 30, "d" to 4, "b" to 31)
    println("array=${render(base + array)}")

    val oneShot = OneShotSequence(listOf("b" to 40, "e" to 5, "b" to 41))
    val sequenceResult = base + oneShot
    println("sequence=${render(sequenceResult)}|iterators=${oneShot.iteratorCalls}")

    val emptyResult = base + emptyList<Pair<String, Int>>()
    println("empty=${render(emptyResult)}|independent=${emptyResult !== base}")

    val independentResult = (base + listOf("f" to 6)) as MutableMap<String, Int>
    independentResult["g"] = 7
    println("afterResultMutation=${render(base)}|result=${render(independentResult)}")

    val nullableBase: Map<String?, Int?> = linkedMapOf(
        Pair<String?, Int?>(null, null),
        Pair<String?, Int?>("n", 1)
    )
    val nullablePairs: Array<Pair<String?, Int?>> = arrayOf(
        Pair<String?, Int?>(null, 2),
        Pair<String?, Int?>("m", null)
    )
    val nullableResult: Map<String?, Int?> = nullableBase + nullablePairs
    println("nullable=${render(nullableResult)}")

    var completed = false
    try {
        base + ThrowingSequence()
        completed = true
    } catch (_: Exception) {
        println("sequenceException=${if (completed) "late" else "immediate"}")
    }
}
