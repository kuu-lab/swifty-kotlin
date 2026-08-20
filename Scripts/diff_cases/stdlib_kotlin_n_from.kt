fun main() {
    val doublePayloadBits = 0x7FF0000000000123L
    val doublePayload = Double.fromBits(doublePayloadBits)
    println(doublePayload.toRawBits() == doublePayloadBits)
    println(Double.fromBits(Long.MIN_VALUE).toRawBits() == Long.MIN_VALUE)

    val floatPayloadBits = 0x7F800123
    val floatPayload = Float.fromBits(floatPayloadBits)
    println(floatPayload.toRawBits() == floatPayloadBits)
    println(Float.fromBits(Int.MIN_VALUE).toRawBits() == Int.MIN_VALUE)
}
