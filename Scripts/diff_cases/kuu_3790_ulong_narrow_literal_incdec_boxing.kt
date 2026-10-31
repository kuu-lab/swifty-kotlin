// Regression (KUU-3790): `var a: ULong = 0u` keeps the `.uintLiteral` expr kind
// while the bound type is ULong. Boxing reads of that slot to `Any`/`Any?` must
// use the ULong box, not `kk_box_uint` — prefix/postfix inc/dec results and
// plain reads alike — or values above UInt32 truncate to 32 bits.
fun prefixDecrementULongLocal(): Any? {
    var value: ULong = 0u
    return --value
}

fun prefixIncrementULongLocal(): Any? {
    var value: ULong = 0u
    ++value
    --value
    return --value
}

fun postfixDecrementULongLocal(): Any? {
    var value: ULong = 0u
    value--
    return value--
}

fun postfixIncrementULongLocal(): Any? {
    var value: ULong = 0u
    value++
    return value++
}

fun readAfterULongWrite(): Any? {
    var value: ULong = 0u
    value = 18446744073709551615uL
    return value
}

fun boxedIsCheckULong(): Boolean {
    var value: ULong = 0u
    val boxed: Any? = --value
    return boxed is ULong && boxed !is UInt
}

private fun matches(value: Any?, expectedValue: String, expectedType: String): Boolean {
    if (value == null) return false
    return value.toString() == expectedValue && value::class.simpleName == expectedType
}

fun box(): String {
    if (!matches(prefixDecrementULongLocal(), "18446744073709551615", "ULong")) return "FAIL ULong local --"
    if (!matches(prefixIncrementULongLocal(), "18446744073709551615", "ULong")) return "FAIL ULong local ++"
    if (!matches(postfixDecrementULongLocal(), "18446744073709551615", "ULong")) return "FAIL ULong postfix --"
    if (!matches(postfixIncrementULongLocal(), "1", "ULong")) return "FAIL ULong postfix ++"
    if (!matches(readAfterULongWrite(), "18446744073709551615", "ULong")) return "FAIL ULong read"
    if (!boxedIsCheckULong()) return "FAIL ULong is-check"
    var a: ULong = 0u
    val r: Any? = --a
    if (!matches(r, "18446744073709551615", "ULong")) return "FAIL ULong val Any? --"
    val rr: Any = r as Any
    if (!matches(rr, "18446744073709551615", "ULong")) return "FAIL ULong Any --"
    val v: ULong = 0u
    val vv: Any? = v
    if (!matches(vv, "0", "ULong")) return "FAIL ULong val direct box"
    return "OK"
}

fun main() {
    println(box())
}
