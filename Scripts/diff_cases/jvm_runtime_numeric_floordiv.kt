// DIFF_JVM
private fun Long.floorDiv(label: String): String = "$label:$this"

private class CustomFloorDiv {
    fun Long.floorDiv(value: Int): Int = value + 40
    fun run(): Int = 5L.floorDiv(3)
}

private fun leftOperand(): Long { print("L"); return -7L }
private fun rightOperand(): Int { print("R"); return 3 }

fun main() {
    val negative = -7L
    val three = 3
    val negativeThree = -3L
    val seven = 7
    val five = 5L
    val longByInt: Long = negative.floorDiv(three)
    val intByLong: Long = seven.floorDiv(negativeThree)
    println(longByInt)
    println(intByLong)
    println(negative.floorDiv(-3))
    println(negative / three)
    println(negative % three)
    println(five.floorDiv("user"))
    println(CustomFloorDiv().run())
    val intMinimum = Int.MIN_VALUE
    val longMinimum = Long.MIN_VALUE
    val negativeOne = -1
    println(intMinimum.floorDiv(negativeOne))
    println(longMinimum.floorDiv(negativeOne))
    try { println(five.floorDiv(0)) } catch (e: ArithmeticException) { println("zero divisor") }
    val byteValue: Byte = -7
    val shortValue: Short = -7
    val byteByInt: Int = byteValue.floorDiv(three)
    val shortByInt: Int = shortValue.floorDiv(three)
    println(byteByInt)
    println(shortByInt)
    println(leftOperand().floorDiv(rightOperand()))
}
