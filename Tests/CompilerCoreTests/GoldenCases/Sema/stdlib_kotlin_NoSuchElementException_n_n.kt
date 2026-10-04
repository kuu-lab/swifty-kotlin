package golden.sema

fun noSuchElementExceptionNoArg(): NoSuchElementException = NoSuchElementException()

fun noSuchElementExceptionMessage(message: String?): NoSuchElementException =
    NoSuchElementException(message)

fun catchNoSuchElementException(): String =
    try {
        throw NoSuchElementException("empty")
    } catch (e: NoSuchElementException) {
        e.message ?: "null"
    }
