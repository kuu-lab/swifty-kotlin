import kotlin.ranges.ULongRange

fun main() {
    val range = ULongRange(1uL, 3uL)
    println(range.endInclusive)
    println(range.endExclusive)
    println(range.isEmpty())
    println(range == ULongRange(1uL, 3uL))
    println(range.hashCode())
    println(range.toString())

    val empty = ULongRange(5uL, 4uL)
    println(empty.isEmpty())
    println(empty == ULongRange(10uL, 0uL))
    println(empty.hashCode())

    try {
        ULongRange(0uL, ULong.MAX_VALUE).endExclusive
    } catch (error: IllegalStateException) {
        println("endExclusive overflow")
    }
}
