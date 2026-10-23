// Regression: prefix increment/decrement results must retain their unsigned
// value and runtime type when returned through Any?.
private var byteProperty: UByte = 0u
private var shortProperty: UShort = 0u
private var intProperty: UInt = 0u
private var longProperty: ULong = 0uL

fun prefixDecrementUByteLocal(): Any? {
    var value: UByte = 0u
    return --value
}

fun prefixIncrementUByteLocal(): Any? {
    var value: UByte = 255u
    return ++value
}

fun prefixDecrementUShortLocal(): Any? {
    var value: UShort = 0u
    return --value
}

fun prefixIncrementUShortLocal(): Any? {
    var value: UShort = 65535u
    return ++value
}

fun prefixDecrementUIntLocal(): Any? {
    var value: UInt = 0u
    return --value
}

fun prefixIncrementUIntLocal(): Any? {
    var value: UInt = 4294967295u
    return ++value
}

fun prefixDecrementULongLocal(): Any? {
    var value: ULong = 0uL
    return --value
}

fun prefixIncrementULongLocal(): Any? {
    var value: ULong = 18446744073709551615uL
    return ++value
}

fun prefixDecrementUByteProperty(): Any? {
    byteProperty = 0u
    return --byteProperty
}

fun prefixIncrementUByteProperty(): Any? {
    byteProperty = 0u
    return ++byteProperty
}

fun prefixDecrementUShortProperty(): Any? {
    shortProperty = 0u
    return --shortProperty
}

fun prefixIncrementUShortProperty(): Any? {
    shortProperty = 0u
    return ++shortProperty
}

fun prefixDecrementUIntProperty(): Any? {
    intProperty = 0u
    return --intProperty
}

fun prefixIncrementUIntProperty(): Any? {
    intProperty = 0u
    return ++intProperty
}

fun prefixDecrementULongProperty(): Any? {
    longProperty = 0uL
    return --longProperty
}

fun prefixIncrementULongProperty(): Any? {
    longProperty = 0uL
    return ++longProperty
}

private fun matches(value: Any?, expectedValue: String, expectedType: String): Boolean {
    if (value == null) return false
    return value.toString() == expectedValue && value::class.simpleName == expectedType
}

fun box(): String {
    if (!matches(prefixDecrementUByteLocal(), "255", "UByte")) return "FAIL UByte --"
    if (!matches(prefixIncrementUByteLocal(), "0", "UByte")) return "FAIL UByte ++"
    if (!matches(prefixDecrementUShortLocal(), "65535", "UShort")) return "FAIL UShort --"
    if (!matches(prefixIncrementUShortLocal(), "0", "UShort")) return "FAIL UShort ++"
    if (!matches(prefixDecrementUIntLocal(), "4294967295", "UInt")) return "FAIL UInt --"
    if (!matches(prefixIncrementUIntLocal(), "0", "UInt")) return "FAIL UInt ++"
    if (!matches(prefixDecrementULongLocal(), "18446744073709551615", "ULong")) return "FAIL ULong --"
    if (!matches(prefixIncrementULongLocal(), "0", "ULong")) return "FAIL ULong ++"
    if (!matches(prefixDecrementUByteProperty(), "255", "UByte")) return "FAIL UByte property --"
    if (!matches(prefixIncrementUByteProperty(), "1", "UByte")) return "FAIL UByte property ++"
    if (!matches(prefixDecrementUShortProperty(), "65535", "UShort")) return "FAIL UShort property --"
    if (!matches(prefixIncrementUShortProperty(), "1", "UShort")) return "FAIL UShort property ++"
    if (!matches(prefixDecrementUIntProperty(), "4294967295", "UInt")) return "FAIL UInt property --"
    if (!matches(prefixIncrementUIntProperty(), "1", "UInt")) return "FAIL UInt property ++"
    if (!matches(prefixDecrementULongProperty(), "18446744073709551615", "ULong")) return "FAIL ULong property --"
    if (!matches(prefixIncrementULongProperty(), "1", "ULong")) return "FAIL ULong property ++"
    return "OK"
}

fun main() {
    println(box())
}
