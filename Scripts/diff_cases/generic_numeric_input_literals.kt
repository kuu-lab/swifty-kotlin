import kotlin.test.assertEquals

fun <T> chooseNumericInput(value: T, other: T): T = other
fun <T> selectNumericInput(value: T, other: T): String = "generic"
fun selectNumericInput(value: Int, other: Int): String = "int"

fun main() {
    val longValue: Long = 0L
    val byteValue: Byte = -1
    val shortValue: Short = 0x3412
    val ubyteValue: UByte = 255u
    val ushortValue: UShort = 65535u
    val ulongValue: ULong = 0uL
    assertEquals(0, longValue)
    assertEquals(longValue, 0)
    assertEquals(actual = longValue, expected = 0)
    assertEquals(expected = 0, actual = longValue)
    assertEquals(-1, byteValue)
    assertEquals(0x3412, shortValue)
    assertEquals(255u, ubyteValue)
    assertEquals(65535u, ushortValue)
    assertEquals(0u, ulongValue)
    assertEquals(11, 11)
    assertEquals(12u, 12u)
    val selected: Byte = chooseNumericInput(byteValue, 37)
    println("selected:" + selected)
    println(selectNumericInput(0, longValue))
    println(selectNumericInput(0, 0))
    println("numeric-literals-ok")
}
