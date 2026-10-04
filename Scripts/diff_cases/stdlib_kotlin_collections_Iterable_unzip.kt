// KSP-997: exercise the generic Iterable overload without widening the test
// to List/Sequence/Array unzip ownership.
class CountingPairs : Iterable<Pair<Int, Int>> {
    var iteratorCalls = 0
    var nextCalls = 0

    override fun iterator(): Iterator<Pair<Int, Int>> {
        iteratorCalls += 1
        return CountingPairsIterator(this)
    }
}

class CountingPairsIterator(private val owner: CountingPairs) : Iterator<Pair<Int, Int>> {
    private var index = 0

    override fun hasNext(): Boolean = index < 3
    override fun next(): Pair<Int, Int> {
        owner.nextCalls += 1
        val pair = when (index) {
            0 -> Pair(3, 30)
            1 -> Pair(3, 30)
            else -> Pair(1, 10)
        }
        index += 1
        return pair
    }
}

class FailingPairs : Iterable<Pair<Int, Int>> {
    var iteratorCalls = 0
    var nextCalls = 0

    override fun iterator(): Iterator<Pair<Int, Int>> {
        iteratorCalls += 1
        return FailingPairsIterator(this)
    }
}

class FailingPairsIterator(private val owner: FailingPairs) : Iterator<Pair<Int, Int>> {
    private var index = 0

    override fun hasNext(): Boolean = index < 4
    override fun next(): Pair<Int, Int> {
        owner.nextCalls += 1
        if (index == 2) throw IllegalStateException("stop")
        val pair = Pair(index, index * 10)
        index += 1
        return pair
    }
}

fun <T, R> splitGeneric(values: Iterable<Pair<T, R>>): Pair<List<T>, List<R>> = values.unzip()

fun main() {
    val empty = emptyList<Pair<Int, String>>().unzip()
    println(empty)

    val single = listOf(Pair(7, "single")).unzip()
    println(single)

    val duplicates = listOf(Pair(2, "x"), Pair(2, "x"), Pair(1, "y")).unzip()
    println(duplicates)

    val nullable: Iterable<Pair<Int?, String?>> = listOf(null to "x", 1 to null)
    println(nullable.unzip())

    val custom = CountingPairs()
    val customResult = custom.unzip()
    println(customResult)
    println("iterators=${custom.iteratorCalls}, next=${custom.nextCalls}")
    println("independent=${customResult.first !== customResult.second}")

    val upcast: Iterable<Pair<Int, String>> = listOf(Pair(8, "upcast"))
    println(upcast.unzip())
    println(splitGeneric(listOf(Pair(9, "generic"))))

    val failing = FailingPairs()
    try {
        failing.unzip()
    } catch (error: IllegalStateException) {
        println("failed: iterators=${failing.iteratorCalls}, next=${failing.nextCalls}")
    }
}
