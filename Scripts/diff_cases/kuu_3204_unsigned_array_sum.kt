@OptIn(ExperimentalUnsignedTypes::class)
fun ubytes(vararg xs: UByte): UInt = xs.sum()

@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    // KUU-3204: unsigned-array sum() used to be unresolved (SEMA-0024).
    println(ubytes(1u, 2u, 3u))
    println(ubyteArrayOf(10u, 20u, 30u).sum())
    println(ushortArrayOf(100u, 200u).sum())
    println(uintArrayOf(4u, 5u).sum())
    println(ulongArrayOf(1uL, 2uL).sum())
    println(UByteArray(0).sum())
    println(UShortArray(0).sum())
    println(ULongArray(0).sum())
}
