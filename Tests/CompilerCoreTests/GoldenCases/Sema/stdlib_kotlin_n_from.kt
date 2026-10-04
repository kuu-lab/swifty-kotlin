package golden.sema

fun main() {
    val doubleValue = fromBits(0x3FF0000000000000L)
    val floatValue = fromBits(0x3F800000)
    println(doubleValue.toRawBits() == 0x3FF0000000000000L)
    println(floatValue.toRawBits() == 0x3F800000)
}
