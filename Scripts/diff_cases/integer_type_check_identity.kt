fun tag(x: Any): String = when (x) {
    is Byte -> "Byte:${x.toInt()}"
    is Short -> "Short:${x.toInt()}"
    is UByte -> "UByte:${x.toInt()}"
    is UShort -> "UShort:${x.toInt()}"
    is UInt -> "UInt:$x"
    is ULong -> "ULong:$x"
    is Int -> "Int:$x"
    is Long -> "Long:$x"
    else -> "other"
}

fun checks(x: Any?): String =
    "${x is Byte},${x is Short},${x is UByte},${x is UShort},${x is UInt},${x is ULong},${x is Int},${x is Long}"

fun safeCasts(x: Any?): String =
    "${x as? Byte},${x as? Short},${x as? UByte},${x as? UShort},${x as? UInt},${x as? ULong},${x as? Int},${x as? Long}"

fun <T> erased(x: T): Any? = x

fun main() {
    val values = listOf<Any>(
        (-128).toByte(), 0x1234.toShort(), 255u.toUByte(), 0x8000u.toUShort(),
        0xDEADBEEFu, 0x8000000000000000uL, 42, Long.MIN_VALUE
    )
    for (x in values) {
        println(tag(x))
        println(checks(x))
        println(safeCasts(x))
    }
    println(checks(null))
    println(checks("other"))
    println(checks(true))
    println(checks(1.0))
    println(checks(1.0f))
    println(checks('a'))
    val b: Byte? = 7.toByte()
    val s: Short? = 300.toShort()
    val n: Byte? = null
    println(tag(b as Any))
    println(tag(s as Any))
    println(checks(n))
    println(n is Byte?)
    println(tag(erased(8.toByte()) as Any))
    println(tag(erased(400.toShort()) as Any))
    println((255u.toUByte() as Any) !is Byte)
    println((0xDEADBEEFu as Any) is UInt)
    try {
        println((42 as Any) as Byte)
    } catch (e: ClassCastException) {
        println("wrong integer cast rejected")
    }
    println((9.toByte() as Any) as Byte)
    println((500.toShort() as Any) as Short)
    val literalByte: Byte = 1
    val literalShort: Short = 2
    val literalUByte: UByte = 3u
    val literalUShort: UShort = 4u
    println(tag(literalByte))
    println(tag(literalShort))
    println(tag(literalUByte))
    println(tag(literalUShort))
}
