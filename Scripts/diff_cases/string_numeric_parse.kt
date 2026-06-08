fun main() {
    println("42".toByte())
    println("-42".toByte())
    println("127".toByteOrNull())
    println("128".toByteOrNull())
    println("abc".toByteOrNull())

    println("1000".toShort())
    println("-1000".toShort())
    println("32767".toShortOrNull())
    println("32768".toShortOrNull())

    println("9999999999".toLong())
    println("-9999999999".toLong())
    println("abc".toLongOrNull())

    println("0.5".toFloat())
    println("-2.0".toFloat())
    println("NaN".toFloat())
    println("Infinity".toFloat())
    println("abc".toFloatOrNull())

    println("true".toBoolean())
    println("TRUE".toBoolean())
    println("yes".toBoolean())
    println("true".toBooleanStrict())
    println("false".toBooleanStrict())
    println("True".toBooleanStrictOrNull())
    println("false".toBooleanStrictOrNull())
}
