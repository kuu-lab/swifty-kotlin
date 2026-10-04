package golden.sema

fun main() {
    val directMax: UShort = UShort.MAX_VALUE
    val directMin: UShort = UShort.MIN_VALUE
    val directBits: Int = UShort.SIZE_BITS
    val directBytes: Int = UShort.SIZE_BYTES
    val explicitMax: UShort = UShort.Companion.MAX_VALUE
    val explicitMin: UShort = UShort.Companion.MIN_VALUE
    val explicitBits: Int = UShort.Companion.SIZE_BITS
    val explicitBytes: Int = UShort.Companion.SIZE_BYTES
    val maxBoundary: UInt = UShort.MAX_VALUE.toUInt()
    val minBoundary: UInt = UShort.MIN_VALUE.toUInt()
    val maxLiteral: UShort = 65535u
    val minLiteral: UShort = 0u
    val bitProduct: Int = UShort.SIZE_BITS * UShort.SIZE_BYTES
    val boxedMax: Any = directMax
    val boxedMin: Any = directMin
    val maxIsUShort: Boolean = boxedMax is UShort
    val minIsUShort: Boolean = boxedMin is UShort
    println(directMax)
    println(directMin)
    println(directBits)
    println(directBytes)
    println(explicitMax)
    println(explicitMin)
    println(explicitBits)
    println(explicitBytes)
    println(maxBoundary)
    println(minBoundary)
    println(maxLiteral)
    println(minLiteral)
    println(bitProduct)
    println(maxIsUShort)
    println(minIsUShort)
}
