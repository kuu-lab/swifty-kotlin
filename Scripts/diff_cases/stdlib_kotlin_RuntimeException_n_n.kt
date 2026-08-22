fun main() {
    val message: String? = "runtime"
    val cause: Throwable? = Exception("cause")
    val noArg = RuntimeException()
    val messageOnly = RuntimeException(message)
    val causeOnly = RuntimeException(cause)
    val messageCause = RuntimeException(message, cause)

    println(noArg.message ?: "null")
    println(messageOnly.message ?: "null")
    println(causeOnly.cause?.message ?: "null")
    println(messageCause.message ?: "null")
    println(messageCause.cause?.message ?: "null")
    println(noArg is Exception)
    println(messageCause is Throwable)
}
