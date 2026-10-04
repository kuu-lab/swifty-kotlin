fun acceptULongRangeProgression(range: ULongProgression): Boolean = true

fun acceptULongRangeClosedRange(range: ClosedRange<ULong>): Boolean = true

fun acceptULongRangeCompanion(companion: Any): Boolean = true

fun main() {
    val range = ULongRange(1uL, 2uL)
    println(acceptULongRangeProgression(range))
    println(acceptULongRangeClosedRange(range))
    println(acceptULongRangeCompanion(ULongRange.Companion))
}
