// KUU-1597 Sema owner: pin LongProgression properties, first/last, and nullable first/last return types; empty/boundary behavior stays in Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n.kt.
private fun inspect(progression: LongProgression) {
    val firstProperty: Long = progression.first
    val lastProperty: Long = progression.last
    val first: Long = progression.first()
    val last: Long = progression.last()
    val firstOrNull: Long? = progression.firstOrNull()
    val lastOrNull: Long? = progression.lastOrNull()
}

fun main() {
    val positive: LongProgression = LongProgression.fromClosedRange(2L, 11L, 3)
    val negative: LongProgression = 10L downTo -10L step 3
    val emptyPositive: LongProgression = LongProgression.fromClosedRange(5L, 1L, 1)
    val emptyNegative: LongProgression = LongProgression.fromClosedRange(1L, 5L, -1)
    val minValue: LongProgression = LongProgression.fromClosedRange(Long.MIN_VALUE, Long.MIN_VALUE, 1)
    val maxValue: LongProgression = LongProgression.fromClosedRange(Long.MAX_VALUE, Long.MAX_VALUE, 1)
    inspect(positive)
    inspect(negative)
    inspect(emptyPositive)
    inspect(emptyNegative)
    inspect(minValue)
    inspect(maxValue)
}
