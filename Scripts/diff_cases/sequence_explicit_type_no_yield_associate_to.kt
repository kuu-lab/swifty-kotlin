// KUU-1221: Explicit builder type arguments must survive a direct terminal chain.
fun main() {
    val destination = mutableMapOf<Int, Int>()
    try {
        sequence<Int> { throw IllegalArgumentException("before yield") }
            .associateTo(destination) { it to it }
    } catch (error: IllegalArgumentException) {
        println(error.message)
    }
    println(destination)

    val emptyDestination = mutableMapOf<Int, Int>()
    println(sequence<Int> { }.associateTo(emptyDestination) { it to it })
    println(iterator<Int> { }.hasNext())
    try {
        val result: Int = iterator<Int> {
            throw IllegalArgumentException("before iterator yield")
        }.next()
        println(result)
    } catch (error: IllegalArgumentException) {
        println(error.message)
    }
}
