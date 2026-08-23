private class NamedThrowable(message: String?) : Throwable(message)

private class OverridingThrowable : Throwable("base") {
    override fun toString(): String = "override"
}

private fun hasSuffix(value: String, suffix: String): Boolean = value.endsWith(suffix)

private fun directToString(message: String?): String = Throwable(message).toString()

private fun anyToString(message: String): String {
    val value: Any = Throwable(message)
    return value.toString()
}

private fun throwableToString(message: String): String {
    val value: Throwable = Throwable(message)
    return value.toString()
}

private fun overridingToString(): String = OverridingThrowable().toString()

private fun caughtToString(message: String): String =
    try {
        throw Throwable(message)
    } catch (error: Throwable) {
        error.toString()
    }

private fun stackTraceSummary(): String {
    val frames = Throwable("trace").getStackTrace()
    val firstFramePresent = frames.size > 0 && frames[0].toString().isNotEmpty()
    return "${frames.size > 0}:$firstFramePresent:${if (frames.size == 0) "empty" else "nonempty"}"
}

fun main() {
    val nullMessage = directToString(null)
    val emptyMessage = directToString("")
    val message = directToString("message")
    val withCause = Throwable("outer", Throwable("inner")).toString()
    val overridden = overridingToString()

    println(nullMessage)
    println(emptyMessage)
    println(message)
    println(anyToString("any"))
    println(throwableToString("base"))
    println(NamedThrowable("subclass").toString())
    println(caughtToString("caught"))
    println(withCause)
    println(overridden)
    println(hasSuffix(nullMessage, "Throwable"))
    println(hasSuffix(emptyMessage, "Throwable: "))
    println(hasSuffix(message, "Throwable: message"))
    println(hasSuffix(anyToString("any"), "Throwable: any"))
    println(hasSuffix(throwableToString("base"), "Throwable: base"))
    println(hasSuffix(NamedThrowable("subclass").toString(), "NamedThrowable: subclass"))
    println(hasSuffix(caughtToString("caught"), "Throwable: caught"))
    println(hasSuffix(withCause, "Throwable: outer"))
    println(hasSuffix(overridden, "override"))
    println(stackTraceSummary())
}
