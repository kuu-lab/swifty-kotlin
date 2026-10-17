package kotlinx.io

@Target(AnnotationTarget.FUNCTION)
annotation class Test

object SinkTestObservations {
    private val entries = mutableListOf<Pair<String, String>>()

    fun reset() {
        entries.clear()
    }

    fun value(expected: Any?, actual: Any?) {
        entries.add("value" to "expected=${expected?.toString() ?: "null"}; actual=${actual?.toString() ?: "null"}")
    }

    fun exceptionTypeMatched() {
        entries.add("exception_type" to "expected exception type matched")
    }

    fun toJson(): String = entries.joinToString(prefix = "[", postfix = "]") { entry ->
        "{\"kind\":${quote(entry.first)},\"value\":${quote(entry.second)}}"
    }

    private fun quote(value: String): String = buildString {
        append('"')
        for (char in value) {
            when (char) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> append(char)
            }
        }
        append('"')
    }
}

fun assertEquals(expected: Any?, actual: Any?) {
    SinkTestObservations.value(expected, actual)
    if (expected != actual) {
        throw IllegalStateException("Expected <$expected> but was <$actual>")
    }
}

inline fun <reified T : Throwable> assertFailsWith(block: () -> Unit): T {
    val failure = try {
        block()
        null
    } catch (thrown: Throwable) {
        thrown
    } ?: throw IllegalStateException("Expected an exception to be thrown")
    if (failure !is T) {
        throw IllegalStateException("Thrown exception did not match the requested type")
    }
    SinkTestObservations.exceptionTypeMatched()
    return failure
}

fun assertArrayEquals(expected: ByteArray, actual: ByteArray) {
    SinkTestObservations.value(expected.contentToString(), actual.contentToString())
    assertEquals(expected.contentToString(), actual.contentToString())
}

private fun hexDigit(char: Char): Int = when (char) {
    in '0'..'9' -> char.code - '0'.code
    in 'a'..'f' -> char.code - 'a'.code + 10
    in 'A'..'F' -> char.code - 'A'.code + 10
    else -> throw IllegalArgumentException("Not a hexadecimal digit: $char")
}

fun String.decodeHex(): ByteArray {
    require(length % 2 == 0) { "Even number of bytes is expected." }
    return ByteArray(length / 2) { index ->
        ((hexDigit(this[index * 2]) shl 4) or hexDigit(this[index * 2 + 1])).toByte()
    }
}
