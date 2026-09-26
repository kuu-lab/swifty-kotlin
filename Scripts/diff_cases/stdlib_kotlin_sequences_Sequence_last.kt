fun main() {
    println(sequenceOf(42).last())
    println(sequenceOf("only").last())
    println(sequenceOf(1, 2, 3).last())
    println(sequenceOf(1, 2, 3).last { it > 1 })
    println(sequenceOf(1, 2, 3).lastOrNull())
    println(emptySequence<Int>().lastOrNull() ?: -1)
    println(sequenceOf(1, 2, 3).lastOrNull { it > 5 } ?: -1)
    println(sequenceOf(1, 2, 3).lastOrNull { it > 1 } ?: -1)

    try {
        emptySequence<Int>().last()
        println("missing-empty")
    } catch (e: NoSuchElementException) {
        println("empty: NSE")
    }

    try {
        sequenceOf(1, 2, 3).last { it > 5 }
        println("missing-predicate")
    } catch (e: NoSuchElementException) {
        println("predicate: NSE")
    }

    // Encounter-order parity: upstream evaluates the predicate on every
    // element in forward order and keeps the last match.
    val evaluated = mutableListOf<Int>()
    val lastMatch = sequenceOf(1, 2, 3, 4).last {
        evaluated.add(it)
        it % 2 == 0
    }
    println(lastMatch)
    println(evaluated)
}
