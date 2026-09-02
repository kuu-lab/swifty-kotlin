// KSP-995: Iterable.take/takeWhile source-backed behavior and early stopping.
class OneShotIterator<T>(
    val values: List<T>,
    val owner: OneShotIterable<T>
) : Iterator<T> {
    var index = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): T {
        if (!hasNext()) throw NoSuchElementException()
        val value = values[index]
        index += 1
        owner.nextCalls += 1
        return value
    }
}

class OneShotIterable<T>(val values: List<T>) : Iterable<T> {
    var iteratorCalls = 0
    var nextCalls = 0

    override fun iterator(): Iterator<T> {
        iteratorCalls += 1
        if (iteratorCalls > 1) throw IllegalStateException("iterator called more than once")
        return OneShotIterator(values, this)
    }
}

fun main() {
    val negative = OneShotIterable(listOf(1, 2, 3))
    try {
        negative.take(-1)
        println("take-negative:missing")
    } catch (e: IllegalArgumentException) {
        println("take-negative:${e.message}:${negative.iteratorCalls}:${negative.nextCalls}")
    }

    val zero = OneShotIterable(listOf(1, 2, 3))
    println("take-zero:${zero.take(0)}:${zero.iteratorCalls}:${zero.nextCalls}")

    val empty = OneShotIterable(emptyList<Int>())
    println("take-empty:${empty.take(3)}:${empty.iteratorCalls}:${empty.nextCalls}")

    val less = OneShotIterable(listOf(1, 2, 3))
    println("take-less:${less.take(2)}:${less.iteratorCalls}:${less.nextCalls}")

    val equal = OneShotIterable(listOf(1, 2, 3))
    println("take-equal:${equal.take(3)}:${equal.iteratorCalls}:${equal.nextCalls}")

    val more = OneShotIterable(listOf(1, 2, 3))
    println("take-more:${more.take(5)}:${more.iteratorCalls}:${more.nextCalls}")

    val nullable: Iterable<String?> = listOf("a", null, "c")
    println("take-nullable:${nullable.take(3)}")

    val firstFalse = OneShotIterable(listOf(1, 2, 3))
    var firstFalseCalls = 0
    println(
        "while-first-false:${firstFalse.takeWhile {
            firstFalseCalls += 1
            it < 2
        }}:${firstFalse.iteratorCalls}:${firstFalse.nextCalls}:$firstFalseCalls"
    )

    val all = OneShotIterable(listOf(1, 2, 3))
    var allCalls = 0
    println("while-all:${all.takeWhile { allCalls += 1; true }}:${all.iteratorCalls}:${all.nextCalls}:$allCalls")

    val none = OneShotIterable(listOf(1, 2, 3))
    var noneCalls = 0
    println("while-none:${none.takeWhile { noneCalls += 1; false }}:${none.iteratorCalls}:${none.nextCalls}:$noneCalls")

    val whileEmpty = OneShotIterable(emptyList<Int>())
    var emptyCalls = 0
    println("while-empty:${whileEmpty.takeWhile { emptyCalls += 1; true }}:${whileEmpty.iteratorCalls}:${whileEmpty.nextCalls}:$emptyCalls")

    val thrown = OneShotIterable(listOf(1, 2, 3))
    var thrownCalls = 0
    try {
        thrown.takeWhile {
            thrownCalls += 1
            if (it == 2) throw IllegalStateException("predicate failed")
            true
        }
        println("while-throw:missing")
    } catch (e: IllegalStateException) {
        println("while-throw:${e.message}:${thrown.iteratorCalls}:${thrown.nextCalls}:$thrownCalls")
    }
}
