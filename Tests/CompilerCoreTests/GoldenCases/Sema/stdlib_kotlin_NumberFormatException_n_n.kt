package golden.sema

fun noArg(): NumberFormatException = NumberFormatException()
fun message(m: String?): NumberFormatException = NumberFormatException(m)

fun catchNumberFormat(): String =
    try {
        throw NumberFormatException("bad number")
    } catch (e: NumberFormatException) {
        e.message ?: "caught"
    }

fun isRuntimeException(e: NumberFormatException): Boolean = e is RuntimeException
fun isException(e: NumberFormatException): Boolean = e is Exception

fun catchRuntimeException(): String =
    try {
        throw NumberFormatException("runtime")
    } catch (e: RuntimeException) {
        e.message ?: "caught"
    }

fun catchException(): String =
    try {
        throw NumberFormatException("exception")
    } catch (e: Exception) {
        e.message ?: "caught"
    }
