fun main() {
    val values = mutableListOf(1, 2, 3)
    val iterator = values.listIterator()

    // Forward traversal
    while (iterator.hasNext()) {
        print("${iterator.next()} ")
    }
    println()

    // Backward traversal
    while (iterator.hasPrevious()) {
        print("${iterator.previous()} ")
    }
    println()
}
