fun main() {
    println("hello".first())
    println("hello".last())
    println("x".single())
    println("".firstOrNull())
    println("".lastOrNull())
    println("".singleOrNull())
    try {
        println("".first())
    } catch (e: NoSuchElementException) {
        println("first empty: ${e.message}")
    }
    try {
        println("ab".single())
    } catch (e: IllegalArgumentException) {
        println("single many: ${e.message}")
    }
}
