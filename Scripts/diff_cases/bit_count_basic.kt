// KSP-643: Int/Long countOneBits / countLeadingZeroBits / countTrailingZeroBits.
// BUG-015: the Long variants used to be dropped between Sema and KIR.
fun main() {
    println(0.countOneBits())
    println(255.countOneBits())
    println((-1).countOneBits())
    println(Int.MIN_VALUE.countOneBits())
    println(Int.MAX_VALUE.countOneBits())
    println(0.countLeadingZeroBits())
    println(1.countLeadingZeroBits())
    println((-1).countLeadingZeroBits())
    println(Int.MIN_VALUE.countLeadingZeroBits())
    println(0.countTrailingZeroBits())
    println(1024.countTrailingZeroBits())
    println(Int.MIN_VALUE.countTrailingZeroBits())

    println(0L.countOneBits())
    println(255L.countOneBits())
    println((-1L).countOneBits())
    println(Long.MIN_VALUE.countOneBits())
    println(Long.MAX_VALUE.countOneBits())
    println(0L.countLeadingZeroBits())
    println(1L.countLeadingZeroBits())
    println((-1L).countLeadingZeroBits())
    println(Long.MIN_VALUE.countLeadingZeroBits())
    println(0L.countTrailingZeroBits())
    println(1024L.countTrailingZeroBits())
    println(Long.MIN_VALUE.countTrailingZeroBits())

    // BUG-015: a compound assignment must keep the Long type of its target.
    var acc = 1024L
    acc -= 1L
    println(acc and 0xFFL)
    println(acc.countOneBits())
}
