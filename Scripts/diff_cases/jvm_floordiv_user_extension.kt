// DIFF_JVM
private fun Long.floorDiv(value: Int): Int = value + 100

fun main() {
    val number = 7L
    val integerDivisor = 3
    val longDivisor = -3L
    println(number.floorDiv(integerDivisor))
    println(number.floorDiv(value = integerDivisor))
    println(number.floorDiv(longDivisor))
    println(number / integerDivisor)
}
