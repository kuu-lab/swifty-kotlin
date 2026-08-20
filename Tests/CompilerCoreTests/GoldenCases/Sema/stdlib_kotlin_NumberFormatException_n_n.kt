package golden.sema

fun noArg(): NumberFormatException = NumberFormatException()
fun message(m: String?): NumberFormatException = NumberFormatException(m)

fun catchNumberFormat(): String =
    try {
        throw NumberFormatException("bad number")
    } catch (e: NumberFormatException) {
        e.message ?: "caught"
    }
