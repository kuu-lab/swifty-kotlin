package diff

fun main() {
    println(IntRange(1, 3).endExclusive)
    println(LongRange(2L, 4L).endExclusive)
    println(CharRange('a', 'c').endExclusive)
    println(UIntRange(1u, 3u).endExclusive)
    println(ULongRange(2uL, 4uL).endExclusive)

    try {
        println(IntRange(Int.MIN_VALUE, Int.MAX_VALUE).endExclusive)
        println("missing int exception")
    } catch (e: IllegalStateException) {
        println("caught int")
    }
    try {
        println(LongRange(Long.MIN_VALUE, Long.MAX_VALUE).endExclusive)
        println("missing long exception")
    } catch (e: IllegalStateException) {
        println("caught long")
    }
    try {
        println(CharRange('a', Char.MAX_VALUE).endExclusive)
        println("missing char exception")
    } catch (e: IllegalStateException) {
        println("caught char")
    }
    try {
        println(UIntRange(0u, UInt.MAX_VALUE).endExclusive)
        println("missing uint exception")
    } catch (e: IllegalStateException) {
        println("caught uint")
    }
    try {
        println(ULongRange(0uL, ULong.MAX_VALUE).endExclusive)
        println("missing ulong exception")
    } catch (e: IllegalStateException) {
        println("caught ulong")
    }
}
