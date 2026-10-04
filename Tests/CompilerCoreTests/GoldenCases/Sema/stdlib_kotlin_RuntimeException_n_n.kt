package golden.sema

fun fromNoArg(): RuntimeException = RuntimeException()

fun fromMessage(message: String?): RuntimeException = RuntimeException(message)

fun fromCause(cause: Throwable?): RuntimeException = RuntimeException(cause)

fun fromMessageCause(message: String?, cause: Throwable?): RuntimeException =
    RuntimeException(message, cause)

fun main() {
    val message: String? = "runtime"
    val exceptionCause: Throwable? = Exception("cause")
    println(fromNoArg().message ?: "null")
    println(fromMessage(message).message ?: "null")
    println(fromCause(exceptionCause).cause?.message ?: "null")
    println(fromMessageCause(message, exceptionCause).cause?.message ?: "null")
}
