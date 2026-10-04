package golden.sema

fun main() {
    val empty = ushortArrayOf()
    val zero = 0.toUShort()
    val maximum = 65535.toUShort()
    val values = ushortArrayOf(zero, maximum)
    val spreadValues = ushortArrayOf(1.toUShort(), 2.toUShort())
    val spread = ushortArrayOf(zero, *spreadValues, maximum)
    println(empty.size)
    println(values.size)
    println(values[0])
    println(values[1])
    println(spread.size)
    println(spread[1])
}
