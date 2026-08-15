// KSP-647: Floating-point bit-pattern conversions.
// Keep raw NaN payloads distinct from canonical toBits() results and preserve
// signed zero, infinity, and exact fromBits/toRawBits round-trips.

fun main() {
    val doublePayloadBits = 0x7FF0000000000123L
    val doublePayload = Double.fromBits(doublePayloadBits)
    println(doublePayload.toRawBits() == doublePayloadBits)
    println(doublePayload.toBits() == 0x7FF8000000000000L)
    println(doublePayload.toRawBits() != doublePayload.toBits())
    println(Double.fromBits(doublePayload.toRawBits()).toRawBits() == doublePayloadBits)

    println((-0.0).toRawBits() == Long.MIN_VALUE)
    println(Double.fromBits(Long.MIN_VALUE).toRawBits() == Long.MIN_VALUE)
    val doubleInfinityBits = 0x7FF0000000000000L
    println(Double.fromBits(doubleInfinityBits).toRawBits() == doubleInfinityBits)

    val floatPayloadBits = 0x7F800123
    val floatPayload = Float.fromBits(floatPayloadBits)
    println(floatPayload.toRawBits() == floatPayloadBits)
    println(floatPayload.toBits() == 0x7FC00000)
    println(floatPayload.toRawBits() != floatPayload.toBits())
    println(Float.fromBits(floatPayload.toRawBits()).toRawBits() == floatPayloadBits)

    println((-0.0f).toRawBits() == Int.MIN_VALUE)
    println(Float.fromBits(Int.MIN_VALUE).toRawBits() == Int.MIN_VALUE)
    val floatInfinityBits = 0x7F800000
    println(Float.fromBits(floatInfinityBits).toRawBits() == floatInfinityBits)
}
