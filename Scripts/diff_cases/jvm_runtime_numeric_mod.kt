// DIFF_JVM
private fun Long.mod(label: String): String = "$label:$this"
private fun Int.mod(value: Int): Int = value + 80

private class CustomMod {
    fun Long.mod(value: Int): Int = value + 40
    fun run(): Int = 5L.mod(3)
}

fun main() {
    val five = 5L
    val negative = -5L
    val three = 3
    val seven = 7
    val minusThree = -3L
    println(five.mod(three))
    println(negative.mod(three))
    println(7.mod(minusThree))
    println(negative % three)
    println(five.mod("user"))
    println(CustomMod().run())
    println(seven.mod(three))
    val minimum = Long.MIN_VALUE
    println(minimum.mod(-1))
    try { println(five.mod(0)) } catch (e: ArithmeticException) { println("zero divisor") }

    val negOne = -1.0
    val one = 1.0
    val posInfinity = Double.POSITIVE_INFINITY
    val negInfinity = Double.NEGATIVE_INFINITY
    println(negOne.mod(posInfinity))
    println(one.mod(negInfinity))
    println(one.mod(posInfinity))
    val negFour = -4.0
    val two = 2.0
    println(1.0 / negFour.mod(two))
    println(one.mod(Double.NaN).isNaN())
    val floatNeg = -1.0f
    val floatPosInfinity = Float.POSITIVE_INFINITY
    println(floatNeg.mod(floatPosInfinity))
    val zero = 0.0
    val floatZero = 0.0f
    val floatOne = 1.0f
    println(one.mod(zero).isNaN())
    println(floatOne.mod(floatZero).isNaN())
    println(1.0 / zero.mod(-two))
}
