fun main() {
    val noArg = NoSuchElementException()
    val message = NoSuchElementException("empty")

    println(noArg.message ?: "null")
    println(message.message ?: "null")
    println(noArg is RuntimeException)
    println(message is Throwable)

    try {
        throw message
    } catch (e: NoSuchElementException) {
        println("caught: ${e.message ?: "null"}")
    }
}
