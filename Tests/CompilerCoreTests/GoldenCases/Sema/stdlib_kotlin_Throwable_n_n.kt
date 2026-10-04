package golden.sema

fun fromNoArg(): Throwable = Throwable()

fun fromMessage(message: String?): Throwable = Throwable(message)

fun fromCause(cause: Throwable?): Throwable = Throwable(cause)

fun fromMessageCause(message: String?, cause: Throwable?): Throwable =
    Throwable(message, cause)

fun main() {
    val message: String? = "throwable"
    val exceptionCause: Throwable? = Exception("cause")
    println(fromNoArg().message ?: "null")
    println(fromMessage(message).message ?: "null")
    println(fromCause(exceptionCause).message ?: "null")
    println(fromCause(exceptionCause).cause?.message ?: "null")
    println(fromMessageCause(message, exceptionCause).message ?: "null")
    println(fromMessageCause(message, exceptionCause).cause?.message ?: "null")
}
