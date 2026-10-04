package golden.sema

fun noArg(): IllegalStateException = IllegalStateException()

fun message(message: String?): IllegalStateException = IllegalStateException(message)

fun cause(cause: Throwable?): IllegalStateException = IllegalStateException(cause)

fun messageAndCause(message: String?, cause: Throwable?): IllegalStateException =
    IllegalStateException(message, cause)
