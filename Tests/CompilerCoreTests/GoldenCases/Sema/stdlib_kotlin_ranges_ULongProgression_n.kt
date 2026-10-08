// KUU-1597 Sema owner: pin ULongProgression properties, first/last, and nullable first/last return types; empty/boundary behavior stays in Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_n.kt.
private fun inspect(progression: ULongProgression) {
    val firstProperty: ULong = progression.first
    val lastProperty: ULong = progression.last
    val first: ULong = progression.first()
    val last: ULong = progression.last()
    val firstOrNull: ULong? = progression.firstOrNull()
    val lastOrNull: ULong? = progression.lastOrNull()
}

fun main() {
    val positive: ULongProgression = ULongProgression.fromClosedRange(2uL, 11uL, 3)
    val negative: ULongProgression = 10uL downTo 0uL step 3
    val emptyPositive: ULongProgression = ULongProgression.fromClosedRange(5uL, 1uL, 1)
    val emptyNegative: ULongProgression = ULongProgression.fromClosedRange(1uL, 5uL, -1)
    val minValue: ULongProgression = ULongProgression.fromClosedRange(ULong.MIN_VALUE, ULong.MIN_VALUE, 1)
    val maxValue: ULongProgression = ULongProgression.fromClosedRange(ULong.MAX_VALUE, ULong.MAX_VALUE, 1)
    inspect(positive)
    inspect(negative)
    inspect(emptyPositive)
    inspect(emptyNegative)
    inspect(minValue)
    inspect(maxValue)
}
