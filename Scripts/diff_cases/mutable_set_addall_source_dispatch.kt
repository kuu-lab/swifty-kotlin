// KUU-2154: Iterable/Sequence extensions must preserve source mutations,
// Collection overload dispatch, and incremental traversal on failure.
class BulkAddSet(val frozen: Boolean = false) : AbstractMutableSet<Int>() {
    val backing = mutableSetOf<Int>()
    var calls = ""
    override val size: Int get() = backing.size
    override fun iterator(): MutableIterator<Int> = backing.iterator()
    override fun add(element: Int): Boolean {
        calls += "A"
        if (frozen) throw UnsupportedOperationException()
        if (element == 99) throw IllegalStateException("add")
        return backing.add(element)
    }
    override fun addAll(elements: Collection<Int>): Boolean {
        calls += "C"
        if (frozen) throw UnsupportedOperationException()
        for (element in elements) {
            if (element == 99) throw IllegalStateException("collection")
        }
        return backing.addAll(elements)
    }
}

class BulkAddIterable(val values: List<Int>, val failure: String = "") : Iterable<Int> {
    override fun iterator(): Iterator<Int> {
        if (failure == "iterator") throw IllegalStateException("iterator")
        return object : Iterator<Int> {
            var index = 0
            override fun hasNext(): Boolean {
                if (index == 1 && failure == "hasNext") throw IllegalStateException("hasNext")
                return index < values.size
            }
            override fun next(): Int {
                if (index == 1 && failure == "next") throw IllegalStateException("next")
                return values[index++]
            }
        }
    }
}

class BulkAddSequence(val values: Iterable<Int>) : Sequence<Int> {
    override fun iterator(): Iterator<Int> = values.iterator()
}

class InheritedBulkAddSet : AbstractMutableSet<Int>() {
    val backing = mutableSetOf<Int>()
    override val size: Int get() = backing.size
    override fun iterator(): MutableIterator<Int> = backing.iterator()
    override fun add(element: Int): Boolean = backing.add(element)
}

fun reportBulkAdd(label: String, set: MutableSet<Int>, input: Iterable<Int>) {
    try { println("$label:${set.addAll(input)}:${set.size}") }
    catch (_: UnsupportedOperationException) { println("$label:UOE:${set.size}") }
    catch (e: IllegalStateException) { println("$label:${e.message}:${set.size}") }
}

fun reportBulkAdd(label: String, set: MutableSet<Int>, input: Sequence<Int>) {
    try { println("$label:${set.addAll(input)}:${set.size}") }
    catch (_: UnsupportedOperationException) { println("$label:UOE:${set.size}") }
    catch (e: IllegalStateException) { println("$label:${e.message}:${set.size}") }
}

fun exerciseBulkAdd(label: String, set: MutableSet<Int>) {
    reportBulkAdd("$label-collection-empty", set, emptyList<Int>())
    reportBulkAdd("$label-collection", set, listOf(1, 1, 2))
    reportBulkAdd("$label-collection-duplicate", set, listOf(1, 2))
    reportBulkAdd("$label-pure-empty", set, BulkAddIterable(emptyList<Int>()))
    reportBulkAdd("$label-pure", set, BulkAddIterable(listOf(2, 3, 3)))
    reportBulkAdd("$label-pure-duplicate", set, BulkAddIterable(listOf(1, 2, 3)))
    reportBulkAdd("$label-sequence-empty", set, sequenceOf<Int>())
    reportBulkAdd("$label-sequence", set, sequenceOf(3, 4, 4))
    reportBulkAdd("$label-sequence-duplicate", set, sequenceOf(1, 2, 3, 4))
    reportBulkAdd("$label-source-sequence", set, BulkAddSequence(BulkAddIterable(listOf(4, 5))))
    println("$label-content:${set.contains(1)}:${set.contains(5)}:${set.contains(6)}")
}

fun exerciseBulkAddFailure(label: String, set: MutableSet<Int>) {
    reportBulkAdd("$label-iterator", set, BulkAddIterable(listOf(10), "iterator"))
    reportBulkAdd("$label-hasNext", set, BulkAddIterable(listOf(11, 12), "hasNext"))
    reportBulkAdd("$label-next", set, BulkAddIterable(listOf(13, 14), "next"))
    reportBulkAdd("$label-sequence-iterator", set, BulkAddSequence(BulkAddIterable(listOf(20), "iterator")))
    reportBulkAdd("$label-sequence-hasNext", set, BulkAddSequence(BulkAddIterable(listOf(21, 22), "hasNext")))
    reportBulkAdd("$label-sequence-next", set, BulkAddSequence(BulkAddIterable(listOf(23, 24), "next")))
    println("$label-content:${set.contains(11)}:${set.contains(12)}:${set.contains(23)}:${set.contains(24)}")
}

fun main() {
    exerciseBulkAdd("native", mutableSetOf<Int>())
    @Suppress("UNCHECKED_CAST")
    val nativeFrozen = buildSet<Int> {} as MutableSet<Int>
    exerciseBulkAdd("native-frozen", nativeFrozen)
    val source = BulkAddSet()
    exerciseBulkAdd("source", source)
    println("source-calls:${source.calls}")
    val frozen = BulkAddSet(true)
    exerciseBulkAdd("frozen", frozen)
    println("frozen-calls:${frozen.calls}")
    exerciseBulkAddFailure("native-failure", mutableSetOf<Int>())
    exerciseBulkAddFailure("source-failure", BulkAddSet())
    val throwing = BulkAddSet()
    reportBulkAdd("throwing-pure", throwing, BulkAddIterable(listOf(30, 99, 31)))
    reportBulkAdd("throwing-sequence", throwing, sequenceOf(32, 99, 33))
    reportBulkAdd("throwing-collection", throwing, listOf(99))
    println("throwing-content:${throwing.contains(30)}:${throwing.contains(31)}:${throwing.contains(32)}:${throwing.contains(33)}")
    println("throwing-calls:${throwing.calls}")
    val control: MutableSet<Int> = BulkAddSet()
    println("control-collection:${control.addAll(listOf(40))}:${control.size}")
    println("control-array:${control.addAll(arrayOf(41, 42))}:${control.size}")
    val concrete = HashSet<Int>()
    println("concrete-pure:${concrete.addAll(BulkAddIterable(listOf(50)))}:${concrete.size}")
    println("concrete-sequence:${concrete.addAll(sequenceOf(51))}:${concrete.size}")
    val inherited: MutableSet<Int> = InheritedBulkAddSet()
    reportBulkAdd("inherited-collection", inherited, listOf(60))
    reportBulkAdd("inherited-pure", inherited, BulkAddIterable(listOf(61)))
    reportBulkAdd("inherited-sequence", inherited, sequenceOf(62))
}
