fun invertByte(value: UByte): UByte = value.inv()
fun invertShort(value: UShort): UShort = value.inv()
fun invertNullableByte(value: UByte?): UByte? = value?.inv()
fun invertNullableShort(value: UShort?): UShort? = value?.inv()

fun checkShort(value: UShort) {
    println(value.inv())
    println(invertShort(value).toInt())
    println(value.inv().inv() == value)
    println(invertNullableShort(value))
}

fun main() {
    val ub = 0xFu.toUByte()
    val us = 0x12u.toUShort()
    println(ub.inv())
    println(us.inv())
    println(ub.inv().toUInt())
    println(us.inv().toUInt())
    println(ub and 0xFu.toUByte())
    println(us xor 0xFFu.toUShort())
    println(ub or 0xF0u.toUByte())

    for (i in 0..255) {
        val value = i.toUByte()
        println(invertByte(value).toInt())
        println(value.inv().inv() == value)
        println(invertNullableByte(value))
    }

    checkShort(0u.toUShort())
    checkShort(1u.toUShort())
    checkShort(us)
    checkShort(0x7FFFu.toUShort())
    checkShort(0x8000u.toUShort())
    checkShort(0xFFFEu.toUShort())
    checkShort(0xFFFFu.toUShort())
    println(invertNullableByte(null))
    println(invertNullableShort(null))

    println(0xFu.inv())
    println(0xFuL.inv())
    println(15.inv())
    println(18L.inv())
}
