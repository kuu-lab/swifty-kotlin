// KUU-1597 Sema owner: pin IntProgression construction and first/last overload return types; empty/boundary behavior stays in Scripts/diff_cases/stdlib_kotlin_ranges_IntProgression_first_last_n.kt.
private fun inspect(progression: IntProgression) {
    val first: Int = progression.first()
    val last: Int = progression.last()
}

fun main() {
    val positive: IntProgression = IntProgression.fromClosedRange(2, 11, 3)
    val negative: IntProgression = 10 downTo -10 step 3
    val emptyPositive: IntProgression = IntProgression.fromClosedRange(5, 1, 1)
    val emptyNegative: IntProgression = IntProgression.fromClosedRange(1, 5, -1)
    val minValue: IntProgression = IntProgression.fromClosedRange(Int.MIN_VALUE, Int.MIN_VALUE, 1)
    val maxValue: IntProgression = IntProgression.fromClosedRange(Int.MAX_VALUE, Int.MAX_VALUE, 1)
    inspect(positive)
    inspect(negative)
    inspect(emptyPositive)
    inspect(emptyNegative)
    inspect(minValue)
    inspect(maxValue)
}
