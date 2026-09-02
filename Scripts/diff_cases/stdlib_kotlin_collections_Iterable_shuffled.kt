import kotlin.random.Random

class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    var iteratorCalls = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls += 1
        if (iteratorCalls > 1) throw IllegalStateException("iterated more than once")
        return values.iterator()
    }
}

fun sameIntMultiset(values: List<Int>, expected: List<Int>): Boolean {
    return values.size == expected.size &&
        values.count { it == 1 } == expected.count { it == 1 } &&
        values.count { it == 2 } == expected.count { it == 2 } &&
        values.count { it == 3 } == expected.count { it == 3 } &&
        values.count { it == 5 } == expected.count { it == 5 }
}

fun main() {
    val original = listOf(1, 1, 2, 3, 5)
    val iterable: Iterable<Int> = original

    // The default overload is nondeterministic; observe only stable invariants.
    val defaultResult = iterable.shuffled()
    println(defaultResult.size)
    println(sameIntMultiset(defaultResult, original))
    println(defaultResult !== iterable)
    println(original == listOf(1, 1, 2, 3, 5))

    // A fixed seed must produce the same order and preserve the multiset.
    val seededOne = iterable.shuffled(Random(42))
    val seededTwo = iterable.shuffled(Random(42))
    println(seededOne)
    println(seededOne == seededTwo)
    println(sameIntMultiset(seededOne, original))
    println(sameIntMultiset(iterable.shuffled(Random(43)), original))

    // Empty and singleton iterables remain valid and preserve their values.
    val empty: Iterable<Int> = emptyList()
    println(empty.shuffled(Random(42)).size)
    val singleton: Iterable<Int> = listOf(42)
    println(singleton.shuffled(Random(42)))

    // Nulls and duplicates are copied and shuffled without loss.
    val nullable: Iterable<String?> = listOf("a", null, "a")
    val nullableResult = nullable.shuffled(Random(42))
    println(nullableResult.size)
    println(nullableResult.count { it == null })
    println(nullableResult.count { it == "a" })

    // Both overloads eagerly consume a custom one-shot iterable exactly once.
    val oneShotDefault = OneShotIterable(listOf(4, 5, 6))
    val defaultOneShotResult = oneShotDefault.shuffled()
    println(defaultOneShotResult.size)
    println(oneShotDefault.iteratorCalls)

    val oneShotSeeded = OneShotIterable(listOf(7, 8, 9))
    val seededOneShotResult = oneShotSeeded.shuffled(Random(42))
    println(seededOneShotResult)
    println(oneShotSeeded.iteratorCalls)
}
