import kotlinx.serialization.json.*

private fun numberFailure(action: () -> Unit): String {
    return try {
        action()
        "no failure"
    } catch (error: NumberFormatException) {
        "NumberFormatException:" + error.message
    }
}

private fun booleanFailure(action: () -> Unit): String {
    return try {
        action()
        "no failure"
    } catch (error: IllegalStateException) {
        "IllegalStateException:" + error.message
    }
}

private fun castFailure(action: () -> Unit): String {
    return try {
        action()
        "no failure"
    } catch (error: IllegalArgumentException) {
        "IllegalArgumentException:" + error.message
    }
}

fun main() {
    val number = JsonPrimitive(42)
    val sameNumber = JsonPrimitive(42L)
    val string = JsonPrimitive("42")
    check(number.content == "42" && !number.isString)
    check(string.content == "42" && string.isString)
    check(number == sameNumber && number.hashCode() == sameNumber.hashCode())
    check(number != string && number.toString() == "42" && string.toString() == "\"42\"")
    check(JsonPrimitive("01").int == 1 && JsonPrimitive("1e2").int == 100)
    check(JsonPrimitive(255.toUByte()).content == "255")
    check(JsonPrimitive(65535.toUShort()).content == "65535")
    check(JsonPrimitive(4294967295u).content == "4294967295")
    check(JsonPrimitive(true).toString() == "true" && JsonPrimitive(false).boolean.not())
    check(JsonPrimitive(null) === JsonNull && JsonPrimitive(null as String?) === JsonNull)
    check(JsonPrimitive(ULong.MAX_VALUE).content == "18446744073709551615")
    check(JsonPrimitive(42).contentOrNull == "42" && JsonNull.contentOrNull == null)
    check(JsonPrimitive(ULong.MAX_VALUE).contentOrNull == "18446744073709551615")
    check(JsonNull.jsonNull === JsonNull && JsonNull.jsonPrimitive === JsonNull)
    val quoted = JsonPrimitive("quote: \" slash: \\ backspace: \b formfeed: \u000C newline: \n return: \r tab: \t control: \u0001")
    println("quoted:" + quoted)
    println("values:" + listOf(number.int, JsonPrimitive("-0").int, JsonPrimitive("1.25").double, JsonPrimitive("2.5").float).joinToString(","))
    println("nullable:" + listOf(JsonPrimitive("2147483648").intOrNull, JsonPrimitive("1.0").longOrNull, JsonPrimitive("NaN").doubleOrNull?.isNaN(), JsonPrimitive("true").booleanOrNull, JsonPrimitive("TRUE").booleanOrNull).joinToString(","))
    println("unsigned:" + JsonPrimitive(ULong.MAX_VALUE))
    println("invalid-cast:" + castFailure { JsonPrimitive(1).jsonNull })
    println("int-overflow:" + numberFailure { JsonPrimitive("2147483648").int })
    println("fraction-as-int:" + numberFailure { JsonPrimitive("1.0").int })
    println("long-overflow:" + numberFailure { JsonPrimitive("9223372036854775808").long })
    println("invalid-bool:" + booleanFailure { JsonPrimitive("yes").boolean })
}
