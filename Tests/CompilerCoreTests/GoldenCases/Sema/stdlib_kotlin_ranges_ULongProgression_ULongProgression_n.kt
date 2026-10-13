// KUU-1597 Sema owner: pin ULongProgression.fromClosedRange overloads and result type; equality, iteration, and formatting stay in Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_ULongProgression_n.kt.
fun main() {
    val positive: ULongProgression = ULongProgression.fromClosedRange(2uL, 11uL, 3L)
    val samePositive: ULongProgression = ULongProgression.fromClosedRange(2uL, 11uL, 3L)
    val negative: ULongProgression = ULongProgression.fromClosedRange(10uL, 0uL, -3L)
    val emptyPositive: ULongProgression = ULongProgression.fromClosedRange(5uL, 1uL, 1L)
    val emptyNegative: ULongProgression = ULongProgression.fromClosedRange(1uL, 5uL, -1L)
}
