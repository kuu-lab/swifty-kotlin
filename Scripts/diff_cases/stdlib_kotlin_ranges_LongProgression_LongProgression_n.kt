fun main() {
    val positive = LongProgression.fromClosedRange(2L, 11L, 3)
    val samePositive = LongProgression.fromClosedRange(2L, 12L, 3)
    val negative = 10L downTo 1L step 3
    val emptyPositive = LongProgression.fromClosedRange(10L, 1L, 3)
    val emptyNegative = LongProgression.fromClosedRange(1L, 10L, -3)

    println("properties=${positive.first},${positive.last},${positive.step}")
    println("positive=$positive")
    println("negative=$negative")
    println("equal=${positive == samePositive},hash=${positive.hashCode() == samePositive.hashCode()}")
    println("emptyEqual=${emptyPositive == emptyNegative},emptyHash=${emptyPositive.hashCode()},${emptyNegative.hashCode()}")
    val iterator = positive.iterator()
    while (iterator.hasNext()) {
        println(iterator.next())
    }
}
