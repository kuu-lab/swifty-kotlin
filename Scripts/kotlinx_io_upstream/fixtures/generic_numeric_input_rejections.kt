import kotlin.test.assertEquals

fun <T : Number> numericBound(value: T, other: T): T = other
fun main() {
    val intValue: Int = 0
    val longValue: Long = 0L
    val byteValue: Byte = 0
    val shortValue: Short = 0
    val ubyteValue: UByte = 0u
    val ushortValue: UShort = 0u
    assertEquals(intValue, longValue)
    assertEquals(128, byteValue)
    assertEquals(-129, byteValue)
    assertEquals(32768, shortValue)
    assertEquals(256u, ubyteValue)
    assertEquals(65536u, ushortValue)
    assertEquals(1L, byteValue)
    assertEquals(1uL, ubyteValue)
    assertEquals(0, "tag")
    numericBound("tag", 0)
}
