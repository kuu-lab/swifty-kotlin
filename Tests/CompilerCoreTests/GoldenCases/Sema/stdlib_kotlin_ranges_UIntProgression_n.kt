// KUU-1597 Sema owner: pin UIntProgression constructor/operator, first/last, and nullable return types; empty/boundary behavior stays in Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_n.kt.
private fun inspect(progression: UIntProgression) {
    val firstProperty: UInt = progression.first
    val lastProperty: UInt = progression.last
    val first: UInt = progression.first()
    val last: UInt = progression.last()
    val firstOrNull: UInt? = progression.firstOrNull()
    val lastOrNull: UInt? = progression.lastOrNull()
}

fun main() {
    val positive: UIntProgression = UIntProgression.fromClosedRange(2u, 11u, 3)
    val negative: UIntProgression = 10u downTo 1u step 3
    val emptyPositive: UIntProgression = UIntProgression.fromClosedRange(10u, 1u, 3)
    val emptyNegative: UIntProgression = UIntProgression.fromClosedRange(1u, 10u, -3)
    val minValue: UIntProgression = UIntProgression.fromClosedRange(UInt.MIN_VALUE, UInt.MIN_VALUE, 1)
    val maxValue: UIntProgression = UIntProgression.fromClosedRange(UInt.MAX_VALUE, UInt.MAX_VALUE, 1)
    inspect(positive)
    inspect(negative)
    inspect(emptyPositive)
    inspect(emptyNegative)
    inspect(minValue)
    inspect(maxValue)
}
