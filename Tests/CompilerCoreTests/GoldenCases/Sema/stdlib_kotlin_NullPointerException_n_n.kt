package golden.sema

fun noArg(): NullPointerException = NullPointerException()
fun message(m: String?): NullPointerException = NullPointerException(m)

fun catchNull(): String =
    try {
        throw NullPointerException("null pointer")
    } catch (e: NullPointerException) {
        e.message ?: "caught"
    }
