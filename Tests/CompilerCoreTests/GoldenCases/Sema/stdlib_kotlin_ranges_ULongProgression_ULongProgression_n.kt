fun main() {
    val positive = ULongProgression.fromClosedRange(2uL, 11uL, 3L)
    val samePositive = ULongProgression.fromClosedRange(2uL, 11uL, 3L)
    val negative = ULongProgression.fromClosedRange(10uL, 0uL, -3L)
    val emptyPositive = ULongProgression.fromClosedRange(5uL, 1uL, 1L)
    val emptyNegative = ULongProgression.fromClosedRange(1uL, 5uL, -1L)

    println("positive=${positive.first},${positive.last},${positive.step}")
    println("negative=${negative.first},${negative.last},${negative.step}")
    println("same=${positive.equals(samePositive)},${positive.hashCode() == samePositive.hashCode()}")
    println("empty=${emptyPositive == emptyNegative},${emptyPositive.hashCode()},${emptyNegative.hashCode()}")
    println("text=${positive.toString()},${negative.toString()}")
    println("iter=${positive.iterator().asSequence().toList()}")
}
