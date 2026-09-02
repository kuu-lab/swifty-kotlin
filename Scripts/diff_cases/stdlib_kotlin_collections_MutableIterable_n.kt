// KSP-1020: predicate-based MutableIterable removal and retention.

class TrackingIterator(
    private val values: ArrayList<Int>,
    private val events: ArrayList<Int>
) : MutableIterator<Int> {
    private var index = 0
    private var lastValue = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): Int {
        val value = values[index]
        index += 1
        lastValue = value
        events.add(100 + value)
        return value
    }

    override fun remove() {
        index -= 1
        values.removeAt(index)
        events.add(200 + lastValue)
    }
}

class TrackingIterable(private val values: ArrayList<Int>) : MutableIterable<Int> {
    val events = ArrayList<Int>()

    override fun iterator(): MutableIterator<Int> = TrackingIterator(values, events)
}

class ThrowingIterator(private val values: ArrayList<Int>) : MutableIterator<Int> {
    private var index = 0

    override fun hasNext(): Boolean = index < values.size

    override fun next(): Int {
        if (values[index] == 2) throw IllegalStateException("iterator stop")
        return values[index++]
    }

    override fun remove() {
        index -= 1
        values.removeAt(index)
    }
}

class ThrowingIterable(private val values: ArrayList<Int>) : MutableIterable<Int> {
    override fun iterator(): MutableIterator<Int> = ThrowingIterator(values)
}

fun main() {
    val empty = mutableListOf<Int>()
    val emptyIterable: MutableIterable<Int> = empty
    println(emptyIterable.removeAll { true })
    println(empty)

    val allKept = mutableListOf(1, 2, 3)
    val allKeptIterable: MutableIterable<Int> = allKept
    println(allKeptIterable.retainAll { true })
    println(allKept)

    val duplicateValues = arrayListOf(1, 2, 2, 3)
    val duplicateIterable: MutableIterable<Int> = duplicateValues
    println(duplicateIterable.removeAll { it == 2 })
    println(duplicateValues)

    val trackingValues = arrayListOf(1, 2, 2, 3)
    val tracking = TrackingIterable(trackingValues)
    println(tracking.removeAll { it == 2 })
    println(trackingValues)
    println(tracking.events)

    val nullableValues: MutableIterable<Int?> = arrayListOf(1, null, 2, null)
    println(nullableValues.retainAll { it == null })
    println(nullableValues)

    val set: MutableSet<Int> = mutableSetOf(1, 2, 3)
    val setValues: MutableIterable<Int> = set
    println(setValues.removeAll { it == 2 })
    println(set.size)
    println(set.contains(2))

    val failureValues = arrayListOf(1, 2, 3)
    try {
        val failureIterable: MutableIterable<Int> = failureValues
        failureIterable.removeAll {
            if (it == 3) throw IllegalStateException("predicate stop")
            it == 2
        }
    } catch (error: IllegalStateException) {
        println("predicate exception")
    }
    println(failureValues)

    val iteratorFailureValues = arrayListOf(1, 2, 3)
    try {
        ThrowingIterable(iteratorFailureValues).removeAll { true }
    } catch (error: IllegalStateException) {
        println("iterator exception")
    }
    println(iteratorFailureValues)
}
