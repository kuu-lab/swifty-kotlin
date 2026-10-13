fun main() {
    val byte: Byte = 6
    val short: Short = 9
    println(byte.times(3))
    println(byte.div(2))
    println(byte.rem(4))
    println(short.times(3))
    println(short.div(2))
    println(short.rem(4))

    val nullableByte: Byte? = byte
    val nullableShort: Short? = short
    println(nullableByte?.times(3))
    println(nullableByte?.div(2))
    println(nullableByte?.rem(4))
    println(nullableShort?.times(3))
    println(nullableShort?.div(2))
    println(nullableShort?.rem(4))

    val nullByte: Byte? = null
    val nullShort: Short? = null
    println(nullByte?.times(3))
    println(nullByte?.div(2))
    println(nullByte?.rem(4))
    println(nullShort?.times(3))
    println(nullShort?.div(2))
    println(nullShort?.rem(4))
}
