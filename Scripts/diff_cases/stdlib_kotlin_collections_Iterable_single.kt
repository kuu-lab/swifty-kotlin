// KSP-992: generic Iterable single-family parity and short-circuit semantics.

class ProbeIterator<T>(
    private val values: List<T>,
    private val owner: ProbeIterable<T>
) : Iterator<T> {
    private var index = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): T {
        val value = values[index]
        index += 1
        owner.nextCalls += 1
        return value
    }
}

class ProbeIterable<T>(private val values: List<T>) : Iterable<T> {
    var iteratorCalls = 0
    var nextCalls = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls += 1
        return ProbeIterator(values, this)
    }
}

fun main() {
    val one = ProbeIterable(listOf(7))
    println(one.single())
    println("${one.iteratorCalls}/${one.nextCalls}")

    try {
        ProbeIterable(emptyList<Int>()).single()
    } catch (e: NoSuchElementException) {
        println("NoSuchElementException:${e.message}")
    }

    val multiple = ProbeIterable(listOf(1, 2, 3))
    try {
        multiple.single()
    } catch (e: IllegalArgumentException) {
        println("IllegalArgumentException:${e.message}:${multiple.nextCalls}")
    }

    var singlePredicateCalls = 0
    val predicateOne = ProbeIterable(listOf(1, 2, 3, 4))
    println(predicateOne.single { value ->
        singlePredicateCalls += 1
        value == 3
    })
    println("${singlePredicateCalls}/${predicateOne.nextCalls}")

    var noMatchPredicateCalls = 0
    val predicateNone = ProbeIterable(listOf(1, 3, 5))
    try {
        predicateNone.single { value ->
            noMatchPredicateCalls += 1
            value % 2 == 0
        }
    } catch (e: NoSuchElementException) {
        println("NoSuchElementException:${e.message}:${noMatchPredicateCalls}/${predicateNone.nextCalls}")
    }

    var multipleMatchPredicateCalls = 0
    val predicateMultiple = ProbeIterable(listOf(1, 2, 4, 6))
    try {
        predicateMultiple.single { value ->
            multipleMatchPredicateCalls += 1
            value % 2 == 0
        }
    } catch (e: IllegalArgumentException) {
        println("IllegalArgumentException:${e.message}:${multipleMatchPredicateCalls}/${predicateMultiple.nextCalls}")
    }

    val nullSingle = ProbeIterable(listOf<Int?>(null))
    println(nullSingle.singleOrNull())
    println("${nullSingle.iteratorCalls}/${nullSingle.nextCalls}")

    val emptyOrNull = ProbeIterable(emptyList<Int>())
    println(emptyOrNull.singleOrNull())
    val multipleOrNull = ProbeIterable(listOf(8, 9, 10))
    println(multipleOrNull.singleOrNull())
    println("${multipleOrNull.iteratorCalls}/${multipleOrNull.nextCalls}")

    var nullablePredicateCalls = 0
    val nullablePredicate = ProbeIterable(listOf<Int?>(null, 2, 4))
    println(nullablePredicate.singleOrNull { value ->
        nullablePredicateCalls += 1
        value == null
    })
    println("${nullablePredicateCalls}/${nullablePredicate.nextCalls}")

    var predicateExceptionCalls = 0
    val predicateException = ProbeIterable(listOf(1, 2, 3))
    try {
        predicateException.singleOrNull { value ->
            predicateExceptionCalls += 1
            if (value == 2) throw IllegalStateException("predicate boom")
            false
        }
    } catch (e: IllegalStateException) {
        println("IllegalStateException:${e.message}:${predicateExceptionCalls}/${predicateException.nextCalls}")
    }
}
