fun main() {
    val noArg = NullPointerException()
    val message = NullPointerException("bad reference")

    println(noArg.message ?: "null")
    println(message.message ?: "bad reference")
    println(noArg is NullPointerException)
    println(message is RuntimeException)
    println(message is Throwable)

    try {
        throw NullPointerException("thrown")
    } catch (e: NullPointerException) {
        println("caught: ${e.message ?: "null"}")
    }
}
