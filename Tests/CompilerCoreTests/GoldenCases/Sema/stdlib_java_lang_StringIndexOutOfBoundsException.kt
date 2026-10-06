package golden.sema

fun noArg(): StringIndexOutOfBoundsException = StringIndexOutOfBoundsException()
fun message(m: String?): IndexOutOfBoundsException = StringIndexOutOfBoundsException(m)
fun index(i: Int): RuntimeException = java.lang.StringIndexOutOfBoundsException(i)

fun catchStringIndex(): String =
    try {
        "abc"[5].toString()
    } catch (e: StringIndexOutOfBoundsException) {
        e.message ?: "string"
    } catch (e: IndexOutOfBoundsException) {
        "parent"
    }
