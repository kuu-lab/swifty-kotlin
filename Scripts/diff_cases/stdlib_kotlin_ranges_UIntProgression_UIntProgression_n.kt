fun main() {
    val positive = UIntProgression.fromClosedRange(2u, 11u, 3)
    val samePositive = UIntProgression.fromClosedRange(2u, 12u, 3)
    val negative = 10u downTo 1u step 3
    val emptyPositive = UIntProgression.fromClosedRange(10u, 1u, 3)
    val emptyNegative = UIntProgression.fromClosedRange(1u, 10u, -3)

    println("properties=${positive.first},${positive.last},${positive.step}")
    println("positive=$positive")
    println("negative=$negative")
    println("equal=${positive == samePositive},hash=${positive.hashCode() == samePositive.hashCode()}")
    println("emptyEqual=${emptyPositive == emptyNegative},emptyHash=${emptyPositive.hashCode()},${emptyNegative.hashCode()}")
}
