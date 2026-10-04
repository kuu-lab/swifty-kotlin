fun main() {
    val doubleRaw = 1.0.toRawBits()
    val doubleCanonical = 1.0.toBits()
    val doubleValue = Double.fromBits(doubleRaw)
    val floatRaw = 1.0f.toRawBits()
    val floatCanonical = 1.0f.toBits()
    val floatValue = Float.fromBits(floatRaw)
    println(doubleValue == 1.0 && doubleRaw == doubleCanonical)
    println(floatValue == 1.0f && floatRaw == floatCanonical)
}
