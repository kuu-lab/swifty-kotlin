package golden.sema

fun main() {
    val empty = floatArrayOf()
    val values = floatArrayOf(1.5f, -2.5f, 3.0f)
    println(empty.size)
    println(values.size)
    println(values[0].toInt())
    println(values[1].toInt())
    println(3.14f.toUInt())
    println((-1.5f).toUInt())
    println(2147483648.0f.toUInt())
    println(Float.POSITIVE_INFINITY.toUInt())
    println(Float.NaN.toULong())
    println(3.14f.toULong())
    println(9223372036854775808.0f.toULong())
    println(Float.POSITIVE_INFINITY.toULong())
}
