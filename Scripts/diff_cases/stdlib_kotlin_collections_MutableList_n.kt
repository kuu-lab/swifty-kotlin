import kotlin.random.Random

private class CountingRandom : Random() {
    var calls = 0

    override fun nextBits(bitCount: Int): Int {
        calls++
        return 0
    }
}

@Suppress("DEPRECATION_ERROR")
fun main() {
    val base = mutableListOf(1, 2, 3)
    val view = base.asReversed()
    view[0] = 4
    view.add(1, 5)
    println("view=${base}|${view}|double=${view.asReversed()}")
    println("readOnly=${(base as List<Int>).asReversed()}")
    val nullable = mutableListOf<Int?>(1, null, 2)
    val nullableView = nullable.asReversed()
    println("nullable=${nullableView}|middle=${nullableView[1]}")

    val indexed = mutableListOf(10, 20, 30)
    println("indexed=${indexed.remove(index = 1)}|${indexed}")
    val element = mutableListOf(10, 20, 30)
    println("element=${element.remove(20)}|${element}")

    val endpoints = mutableListOf(1, 2, 3)
    println("first=${endpoints.removeFirst()}|${endpoints.removeFirstOrNull()}|${endpoints}")
    println("last=${endpoints.removeLast()}|${endpoints.removeLastOrNull()}|${endpoints}")
    println("nulls=${mutableListOf<Int>().removeFirstOrNull()}|${mutableListOf<Int>().removeLastOrNull()}")

    val seen = mutableListOf<Int>()
    val predicates = mutableListOf(1, 2, 3, 4)
    println("removeAll=${predicates.removeAll { seen.add(it); it % 2 == 0 }}|${predicates}|seen=${seen}")
    println("retainAll=${predicates.retainAll { it == 1 }}|${predicates}")
    val throwing = mutableListOf(1, 2, 3, 4)
    try {
        throwing.removeAll { if (it == 3) throw IllegalStateException("boom"); it == 1 }
    } catch (error: IllegalStateException) {
        println("predicateException=${error.message}|${throwing}")
    }

    val reversed = mutableListOf(1, 2, 3)
    reversed.reverse()
    println("reverse=${reversed}")

    val defaultShuffle = mutableListOf(1, 2, 3, 4)
    defaultShuffle.shuffle()
    println("shuffleDefault=${defaultShuffle.size}|${defaultShuffle.sorted()}")
    val seededA = mutableListOf(1, 2, 3, 4)
    val seededB = mutableListOf(1, 2, 3, 4)
    seededA.shuffle(Random(42))
    seededB.shuffle(Random(42))
    println("shuffleSeeded=${seededA}|same=${seededA == seededB}")
    val countingRandom = CountingRandom()
    val counted = mutableListOf(1, 2, 3, 4)
    counted.shuffle(countingRandom)
    println("shuffleCounting=${counted}|calls=${countingRandom.calls}")
}
