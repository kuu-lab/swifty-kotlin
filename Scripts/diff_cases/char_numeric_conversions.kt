fun main() {
    val high = '\uD800'
    val max = '\uFFFF'

    println(high.toByte())
    println(high.toShort())
    println(high.toInt())
    println(high.toLong())
    println(high.code.toUInt())
    println(high.code.toULong())
    println(max.code)
    println(max.code.toUInt())
    println(max.code.toULong())
}
