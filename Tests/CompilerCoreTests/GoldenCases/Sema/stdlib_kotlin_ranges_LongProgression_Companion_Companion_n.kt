private fun inspect(progression: LongProgression): Long = progression.step

fun main() {
    val positive = LongProgression.fromClosedRange(2L, 11L, 3L)
    val negative = LongProgression.fromClosedRange(10L, 0L, -3L)
    val largeStep = LongProgression.fromClosedRange(0L, Long.MAX_VALUE, Long.MAX_VALUE)
    println(inspect(positive))
    println(inspect(negative))
    println(inspect(largeStep))
}
