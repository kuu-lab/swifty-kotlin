fun main() {
    val message: String? = "argument"
    val cause: Throwable? = Exception("cause")
    val noArg = IllegalArgumentException()
    val messageOnly = IllegalArgumentException(message)
    val causeOnly = IllegalArgumentException(cause)
    val messageCause = IllegalArgumentException(message, cause)

    println(noArg.message ?: "null")
    println(messageOnly.message ?: "null")
    println(causeOnly.cause?.message ?: "null")
    println(messageCause.message ?: "null")
    println(messageCause.cause?.message ?: "null")
    println(noArg is RuntimeException)
    println(messageCause is Throwable)
}
