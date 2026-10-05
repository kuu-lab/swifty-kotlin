// KUU-1152: boxed generic receivers must be unboxed at concrete primitive calls.
fun <T : Int> bitsI(x: T) {
    println(x.countOneBits())
    println(x.countLeadingZeroBits())
    println(x.countTrailingZeroBits())
    println(x.takeHighestOneBit())
    println(x.takeLowestOneBit())
}

fun <T : Long> bitsL(x: T) {
    println(x.countOneBits())
    println(x.countLeadingZeroBits())
    println(x.countTrailingZeroBits())
    println(x.takeHighestOneBit())
    println(x.takeLowestOneBit())
}

// Keep unsigned coverage independent of the stdlib additions in KUU-1098.
fun UInt.receiverOnes(): Int = toInt().countOneBits()
fun UInt.receiverLeadingZeros(): Int = toInt().countLeadingZeroBits()
fun UInt.receiverTrailingZeros(): Int = toInt().countTrailingZeroBits()
fun ULong.receiverOnes(): Int = toLong().countOneBits()
fun ULong.receiverLeadingZeros(): Int = toLong().countLeadingZeroBits()
fun ULong.receiverTrailingZeros(): Int = toLong().countTrailingZeroBits()

fun <T : UInt> bitsU(x: T) {
    println(x.receiverOnes())
    println(x.receiverLeadingZeros())
    println(x.receiverTrailingZeros())
}

fun <T : ULong> bitsUL(x: T) {
    println(x.receiverOnes())
    println(x.receiverLeadingZeros())
    println(x.receiverTrailingZeros())
}

fun <T : UInt> idU(x: T): UInt = x
fun <T : ULong> idUL(x: T): ULong = x
fun <T : Int> forwardI(x: T) = bitsI(x)
fun <T : Long> forwardL(x: T) = bitsL(x)
fun <T : UInt> forwardU(x: T) = bitsU(x)
fun <T : ULong> forwardUL(x: T) = bitsUL(x)

fun main() {
    bitsI(0)
    bitsI(1)
    bitsI(0x00010000)
    bitsI(-1)
    bitsI(Int.MIN_VALUE)
    bitsI(Int.MAX_VALUE)
    forwardI(0x55AA55AA)
    bitsL(0L)
    bitsL(1L)
    bitsL(0x100000000L)
    bitsL(-1L)
    bitsL(Long.MIN_VALUE)
    bitsL(Long.MAX_VALUE)
    forwardL(0x55AA55AA55AA55AAL)
    bitsU(0u)
    bitsU(1u)
    bitsU(0x00010000u)
    bitsU(0xFF00FF00u)
    bitsU(0x80000000u)
    bitsU(UInt.MAX_VALUE)
    forwardU(0x55AA55AAu)
    bitsUL(0uL)
    bitsUL(1uL)
    bitsUL(0x100000000uL)
    bitsUL(0x8000000000000000uL)
    bitsUL(ULong.MAX_VALUE)
    forwardUL(0x55AA55AA55AA55AAuL)
    println(idU(0x00010000u))
    println(idUL(0x8000000000000000uL))
}
