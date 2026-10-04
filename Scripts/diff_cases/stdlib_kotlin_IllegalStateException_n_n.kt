fun main() {
    val noArg = IllegalStateException()
    val message = IllegalStateException("message")
    val cause = IllegalStateException(RuntimeException("cause"))
    val javaUtilCause = IllegalStateException(NoSuchElementException("missing"))
    val messageAndCause = IllegalStateException("both", IllegalArgumentException("root"))

    println(noArg.message ?: "null")
    println(message.message ?: "null")
    println(cause.message ?: "null")
    println(cause.cause?.message ?: "null")
    println(javaUtilCause.message ?: "null")
    println(messageAndCause.message ?: "null")
    println(messageAndCause.cause?.message ?: "null")
    println(messageAndCause.cause is IllegalArgumentException)
    println(messageAndCause is RuntimeException)
    println(messageAndCause is Throwable)

    try {
        throw messageAndCause
    } catch (e: IllegalStateException) {
        println("caught: ${e.message}:${e.cause?.message}")
    }
}
