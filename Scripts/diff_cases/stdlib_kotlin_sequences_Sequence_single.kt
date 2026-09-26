fun main() {
    println(sequenceOf(42).single())
    println(sequenceOf("only").single())
    println(sequenceOf(1, 2, 3).single { it > 2 })
    println(sequenceOf(1, 2, 3).singleOrNull { it > 2 })
    println(sequenceOf(1, 2).singleOrNull() ?: -1)
    println(emptySequence<Int>().singleOrNull() ?: -1)
    println(sequenceOf(1, 2, 3).singleOrNull { it > 5 } ?: -1)
    println(sequenceOf(1, 2, 3).singleOrNull { it > 1 } ?: -1)

    try {
        emptySequence<Int>().single()
        println("missing-empty")
    } catch (e: NoSuchElementException) {
        println("empty: NSE")
    }

    try {
        sequenceOf(1, 2).single()
        println("missing-multiple")
    } catch (e: IllegalArgumentException) {
        println("multiple: IAE")
    }

    try {
        sequenceOf(1, 2, 3).single { it > 5 }
        println("missing-predicate")
    } catch (e: NoSuchElementException) {
        println("predicate: NSE")
    }

    try {
        sequenceOf(1, 2, 3).single { it > 1 }
        println("missing-predicate-multiple")
    } catch (e: IllegalArgumentException) {
        println("predicate: IAE")
    }

    // Infinite-sequence parity: upstream throws IllegalArgumentException /
    // returns null without consuming the whole sequence.
    try {
        generateSequence(1) { it + 1 }.single()
        println("missing-infinite")
    } catch (e: IllegalArgumentException) {
        println("infinite: IAE")
    }
    println(generateSequence(1) { it + 1 }.singleOrNull() ?: "null")
}
