fun main() {
    val ascending = CharProgression.fromClosedRange('a', 'f', 2)
    val descending = CharProgression.fromClosedRange('f', 'a', -2)
    val empty = CharProgression.fromClosedRange('z', 'a', 1)

    println("${ascending.first()} ${ascending.firstOrNull()} ${ascending.last()} ${ascending.lastOrNull()}")
    println("${descending.first()} ${descending.firstOrNull()} ${descending.last()} ${descending.lastOrNull()}")
    println("${empty.firstOrNull() == null} ${empty.lastOrNull() == null}")
    try {
        empty.first()
    } catch (e: NoSuchElementException) {
        println(e.message)
    }
    try {
        empty.last()
    } catch (e: NoSuchElementException) {
        println(e.message)
    }
}
