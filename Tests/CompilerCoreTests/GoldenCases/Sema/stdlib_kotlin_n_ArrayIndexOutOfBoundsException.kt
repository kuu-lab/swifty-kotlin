package golden.sema

fun noArg(): ArrayIndexOutOfBoundsException = ArrayIndexOutOfBoundsException()
fun message(m: String?): ArrayIndexOutOfBoundsException = ArrayIndexOutOfBoundsException(m)

fun catchArrayIndex(): String =
    try {
        throw ArrayIndexOutOfBoundsException("out of bounds")
    } catch (e: ArrayIndexOutOfBoundsException) {
        e.message ?: "caught"
    }
