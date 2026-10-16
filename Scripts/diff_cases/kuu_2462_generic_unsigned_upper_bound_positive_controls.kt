fun <T : UByte> explicitUByte(value: T): String = "OK"
fun <T : UShort> explicitUShort(value: T): String = "OK"
fun <T : UInt> inferredUInt(value: T): String = "OK"
fun concreteUByte(value: UByte): String = "OK"
fun box(): String {
    if (explicitUByte<UByte>(1u) != "OK") return "Fail explicit UByte"
    if (explicitUShort<UShort>(1u) != "OK") return "Fail explicit UShort"
    if (inferredUInt(1u) != "OK") return "Fail UInt"
    if (concreteUByte(1u) != "OK") return "Fail concrete UByte"
    return "OK"
}
fun main() { println(box()) }
