// DIFF_JVM
// KUU-3967: unsigned integer literals retarget to the unsigned type the
// expected type demands. `x and 0xFFU` types `0xFFU` as ULong for
// ULong.and(ULong) — the same literal stays UInt for UInt.and(UInt) and
// narrows to UByte/UShort where it fits. Regression coverage for the
// kotlin-multiplatform-bignum ConversionUtils shape
// `(x shr (56 - (it*8))) and 0xFFU`.
fun main() {
    // ULong receiver + `u`-suffixed literal arguments
    println(0x1234UL and 0xFFU)
    println(0x1234UL or 0x0FU)
    println(0x1234UL xor 0b1010U)
    println(0x1234UL and 255U)
    println(0x1234UL.and(0xFFU))

    // Bignum mask shape: literal after a shift result
    val it = 6
    println((0x1234UL shr (56 - (it * 8))) and 0xFFU)

    // UInt receiver keeps the literal at UInt
    println(0x1234u and 0xFFU)
    println(0x1234u or 0x0FU)
    println(0x1234u xor 0b1010U)

    // Narrow retargets where the value fits
    val ub: UByte = 0xABu
    val us: UShort = 0xFF00u
    println(ub and 0x0FU)
    println(us or 0x0F00U)
    println(ub xor 0xFFU)

    // Shifts take an Int distance; receiver stays unsigned
    println(0x10UL shl 3)
    println(0x10UL shr 3)
    println(0x10u shl 3)
    println(0x10u shr 3)

    // Expected-type positions outside member calls
    val mask: ULong = 0xFFU
    val byteMask: UByte = 0xFFU
    val shortMask: UShort = 0xFF00U
    fun takesULong(v: ULong): ULong = v
    println(takesULong(0xFFU))
    println(mask)
    println(byteMask)
    println(shortMask)
}
