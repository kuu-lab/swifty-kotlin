// KUU-1040: constructor properties may override Throwable.message and cause
// through IllegalArgumentException, including a non-null String message.
class ParseException(
    override val message: String,
    override val cause: Throwable? = null
) : IllegalArgumentException(message, cause)

fun main() {
    val root = IllegalStateException("root")
    val parsed = ParseException("invalid input", root)
    println(parsed.message)
    println(parsed.cause === root)

    val exception: Exception = parsed
    println(exception.message)
    println(exception.cause?.message)

    val throwable: Throwable = parsed
    println(throwable.message)
    println(throwable.cause === root)

    val withoutCause = ParseException("missing field")
    println(withoutCause.message)
    println(withoutCause.cause == null)

    try {
        throw parsed
    } catch (e: IllegalArgumentException) {
        println(e.message)
        println(e.cause?.message)
    }
}
