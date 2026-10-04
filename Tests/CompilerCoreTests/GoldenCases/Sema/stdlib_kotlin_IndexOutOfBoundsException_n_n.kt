package golden.sema

fun noArg(): IndexOutOfBoundsException = IndexOutOfBoundsException()
fun message(m: String?): IndexOutOfBoundsException = IndexOutOfBoundsException(m)

fun catchIndex(): String =
    try {
        throw IndexOutOfBoundsException("out of bounds")
    } catch (e: IndexOutOfBoundsException) {
        e.message ?: "caught"
    }
