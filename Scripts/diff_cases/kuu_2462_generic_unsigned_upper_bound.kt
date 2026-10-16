fun <T : UByte> asUByte(value: T): String = "OK"
fun <T : UShort> asUShort(value: T): String = "OK"
fun box(): String {
    if (asUByte(1u) != "OK") return "Fail UByte"
    if (asUShort(1u) != "OK") return "Fail UShort"
    return "OK"
}
fun main() { println(box()) }
