fun main() {
    println(Short.MAX_VALUE)
    println(Short.MIN_VALUE)
    println(Short.SIZE_BITS)
    println(Short.SIZE_BYTES)
    println(Short.Companion.MAX_VALUE)
    println(Short.Companion.MIN_VALUE)
    println(Short.Companion.SIZE_BITS)
    println(Short.Companion.SIZE_BYTES)
    println(Short.MAX_VALUE.toShort())
    println(Short.MIN_VALUE.toShort())
    val boxedMax: Any = Short.MAX_VALUE
    val boxedMin: Any = Short.MIN_VALUE
    println(boxedMax)
    println(boxedMin)
}
