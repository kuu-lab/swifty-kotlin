// KOTLINC_FLAGS: -Xjdk-release=17
private var trace = ""

private fun choose(): Boolean {
    trace += "C"
    return true
}

private fun argument(): String {
    trace += "A"
    return "42"
}

private fun parse(value: Int): String = "int:$value"
private fun parse(value: String): String = "string:$value"
private fun other(value: String): String = "other:$value"
private fun nullableParse(value: Int): String? = if (value == 0) null else "int"
private fun nullableParse(value: String): String? = value
private fun nullableOther(value: Int): String? = null
private fun narrow(value: Byte): String = "byte"
private fun narrow(value: String): String = value
private fun narrowOther(value: Byte): String = "other-byte"
private fun anyOther(value: Any): String = "any"
private fun intOther(value: Int): String = "int"

fun main() {
    println((when (true) {
        true -> String::toInt
        false -> String::toBoolean
    })("42"))
    println((if (true) String::toInt else String::toBoolean)("42"))
    println((when (true) { true -> ::parse; false -> ::other })("42"))
    println((when (choose()) { true -> ::parse; false -> ::other })(argument()))
    println(trace)
    val value: Any = "42"
    println((when (value as String) { "42" -> ::parse; else -> ::other })(value))
    val nullable = (if (true) ::nullableParse else ::nullableOther)(0)
    println(nullable?.length ?: -1)
    println((if (true) ::narrow else ::narrowOther)(127))
    println((when (1) { 0 -> ::parse; 1 -> ::anyOther; else -> ::intOther })(1))
}
