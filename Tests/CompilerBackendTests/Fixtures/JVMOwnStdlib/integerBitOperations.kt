// Int and Long bit helpers exposed by the bundled JVM stdlib.
fun main() {
    println(5.countOneBits())
    println(16.countTrailingZeroBits())
    println(8.countLeadingZeroBits())
    println(1.rotateLeft(3))
    println(16.rotateRight(2))

    println(0.countOneBits())
    println((-1).countOneBits())
    println(0.countLeadingZeroBits())
    println(Int.MIN_VALUE.countTrailingZeroBits())
    println(0L.countOneBits())
    println((-1L).countOneBits())
    println(0L.countLeadingZeroBits())
    println(Long.MIN_VALUE.countTrailingZeroBits())

    println(1.rotateLeft(-1))
    println(1.rotateRight(32))
    println(1L.rotateLeft(-1))
    println(1L.rotateRight(64))
    println(1.rotateLeft(Int.MIN_VALUE))
    println(1.rotateRight(Int.MAX_VALUE))
    println(1L.rotateLeft(Int.MIN_VALUE))
    println(1L.rotateRight(Int.MAX_VALUE))
}
