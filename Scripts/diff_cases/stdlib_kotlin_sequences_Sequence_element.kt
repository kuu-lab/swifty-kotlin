fun main() {
    println(sequenceOf(10, 20, 30).elementAt(1))
    println(sequenceOf(10, 20, 30).elementAtOrElse(9) { -1 })
    println(sequenceOf(10, 20, 30).elementAtOrElse(-2) { it * 100 })
    println(sequenceOf(10, 20, 30).elementAtOrNull(2))
    println(sequenceOf(10, 20, 30).elementAtOrNull(9) ?: "null")
    println(sequenceOf(10, 20, 30).elementAtOrNull(-1) ?: "null")

    // Lazy traversal: a finite index into an infinite sequence still terminates.
    println(generateSequence(0) { it + 1 }.elementAt(5))

    try {
        sequenceOf(1, 2, 3).elementAt(10)
        println("missing-oob")
    } catch (e: IndexOutOfBoundsException) {
        println("oob: ${e.message}")
    }

    try {
        sequenceOf(1, 2, 3).elementAt(-1)
        println("missing-neg")
    } catch (e: IndexOutOfBoundsException) {
        println("neg: ${e.message}")
    }
}
