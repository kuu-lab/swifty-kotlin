fun reportFailure(iterator: Iterator<*>) {
    try { iterator.hasNext(); println("missing first failure") } catch (failure: IllegalArgumentException) { println("caught:" + failure.message) }
    try { iterator.hasNext(); println("missing failed hasNext") } catch (failure: IllegalStateException) { println("hasNext:" + failure.message) }
    try { iterator.next(); println("missing failed next") } catch (failure: IllegalStateException) { println("next:" + failure.message) }
}
fun main() {
    var zipFirst = true
    val zipped = sequenceOf(1, 2, 3, 4).map { if (it == 3 && zipFirst) { zipFirst = false; throw IllegalArgumentException("zip source") }; it }.zipWithNext().iterator()
    println(zipped.next()); reportFailure(zipped)
    var overlapFirst = true
    val overlap = sequenceOf(1, 2, 3, 4).map { if (it == 3 && overlapFirst) { overlapFirst = false; throw IllegalArgumentException("overlap source") }; it }.windowed(2, 1).iterator()
    println(overlap.next()); reportFailure(overlap)
    var gapFirst = true
    val gap = sequenceOf(1, 2, 3, 4, 5, 6).map { if (it == 3 && gapFirst) { gapFirst = false; throw IllegalArgumentException("gap source") }; it }.windowed(2, 4).iterator()
    println(gap.next()); reportFailure(gap)
    val empty = emptySequence<Int>().windowed(2).iterator()
    println(empty.hasNext())
    try { empty.next() } catch (failure: NoSuchElementException) { println("empty next") }
    println(empty.hasNext())
}
