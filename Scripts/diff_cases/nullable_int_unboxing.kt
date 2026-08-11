fun nullableInt(x: Int): Int? = if (x > 0) x else null

fun main() {
    val v = nullableInt(255)!!
    println(v.toByte())
    println(v.toShort())
    println(v.toInt())
    println(v.toLong())
    println(v.toChar())
    println(v.toFloat().toInt())
    println(v.toDouble().toInt())
    println(v.toUByte())
    println(v.toUShort())
    println(v.toUInt())
    println(v.toULong())

    // KSP-662 regression: Char.digitToIntOrNull used through !! must unbox
    // before Int arithmetic and conversions.
    println('a'.digitToIntOrNull(16)!!.toByte())
    println('a'.digitToIntOrNull(16)!!.toLong())
}
