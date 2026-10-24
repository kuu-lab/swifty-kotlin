// Sequence.minus(element), minusElement and the `-` operator return a lazy
// sequence: nothing is evaluated until the result is iterated, an infinite
// receiver can be cut with take(), and only the first matching element is
// removed on every iteration.
fun main() {
    // An infinite receiver must not be drained when the sequence is built.
    println(generateSequence(1) { it + 1 }.minus(3).take(5).toList())
    println(generateSequence(1) { it + 1 }.minusElement(3).take(5).toList())
    println((generateSequence(1) { it + 1 } - 3).take(5).toList())

    // The receiver is not touched before the result is iterated, and it is
    // consumed one element at a time.
    val visited = sequenceOf(1, 2, 3).onEach { println("visit $it") }
    val reduced = visited.minus(2)
    println("built")
    println(reduced.first())
    println(reduced.toList())

    // Only the first occurrence is removed.
    println(sequenceOf(1, 2, 1, 2).minus(2).toList())

    // Every iteration starts from scratch, so the removal repeats.
    val twice = sequenceOf(1, 2, 3, 2).minus(2)
    println(twice.toList())
    println(twice.toList())
}
