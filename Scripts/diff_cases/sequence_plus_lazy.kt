// Sequence.plus (every overload), plusElement and the `+` operator return a
// lazy sequence: nothing is evaluated until the result is iterated, an
// infinite receiver can be cut with take(), and `other` is only read once the
// receiver is exhausted.
fun main() {
    // An infinite receiver must not be drained when the sequence is built.
    println(generateSequence(1) { it + 1 }.plus(sequenceOf(0)).take(2).toList())
    println((generateSequence(1) { it + 1 } + listOf(0)).take(3).toList())
    println((generateSequence(1) { it + 1 } + arrayOf(0)).take(3).toList())
    println(generateSequence(1) { it + 1 }.plus(0).take(2).toList())
    println(generateSequence(1) { it + 1 }.plusElement(0).take(2).toList())
    println((generateSequence(1) { it + 1 } + 0).take(2).toList())

    // Neither side runs before the result is iterated, and the receiver is
    // consumed one element at a time.
    val visited = sequenceOf(1, 2, 3).onEach { println("visit $it") }
    val combined = visited.plus(sequenceOf(9).onEach { println("other $it") })
    println("built")
    println(combined.first())
    println(combined.toList())

    // `other` is read when the receiver is exhausted, not when plus() is called.
    val other = mutableListOf(1)
    val lateOther = sequenceOf(0).plus(other)
    other.add(2)
    println(lateOther.toList())

    // The result is as re-iterable as its sources.
    val twice = sequenceOf(1, 2).plus(sequenceOf(3, 4))
    println(twice.toList())
    println(twice.toList())
}
