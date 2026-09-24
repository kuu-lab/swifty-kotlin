// KUU-745: Sequence.elementAt must throw a catchable IndexOutOfBoundsException.
fun main() {
    try {
        sequenceOf(1, 2, 3).elementAt(10)
        println("missing-positive")
    } catch (e: IndexOutOfBoundsException) {
        println("caught-index")
    }

    try {
        sequenceOf(1, 2, 3).elementAt(-1)
        println("missing-negative")
    } catch (e: Exception) {
        println("caught-exception")
    }
}
