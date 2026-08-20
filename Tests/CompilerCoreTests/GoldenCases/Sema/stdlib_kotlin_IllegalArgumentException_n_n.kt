package golden.sema

fun fromNoArg(): IllegalArgumentException = IllegalArgumentException()

fun fromMessage(message: String?): IllegalArgumentException = IllegalArgumentException(message)

fun fromCause(cause: Throwable?): IllegalArgumentException = IllegalArgumentException(cause)

fun fromMessageCause(message: String?, cause: Throwable?): IllegalArgumentException =
    IllegalArgumentException(message, cause)

fun main() {
    val message: String? = "argument"
    val exceptionCause: Throwable? = Exception("cause")
    println(fromNoArg().message ?: "null")
    println(fromMessage(message).message ?: "null")
    println(fromCause(exceptionCause).cause?.message ?: "null")
    println(fromMessageCause(message, exceptionCause).cause?.message ?: "null")
}
