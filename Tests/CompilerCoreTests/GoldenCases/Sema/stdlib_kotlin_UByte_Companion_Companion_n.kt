package golden.sema

fun main() {
    val directMax: UByte = UByte.MAX_VALUE
    val directMin: UByte = UByte.MIN_VALUE
    val directBits: Int = UByte.SIZE_BITS
    val directBytes: Int = UByte.SIZE_BYTES
    val explicitMax: UByte = UByte.Companion.MAX_VALUE
    val explicitMin: UByte = UByte.Companion.MIN_VALUE
    val explicitBits: Int = UByte.Companion.SIZE_BITS
    val explicitBytes: Int = UByte.Companion.SIZE_BYTES
    val maxBoundary: UInt = UByte.MAX_VALUE.toUInt()
    val minBoundary: UInt = UByte.MIN_VALUE.toUInt()
    val bitProduct: Int = UByte.SIZE_BITS * UByte.SIZE_BYTES
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
    println(bitProduct)
}
