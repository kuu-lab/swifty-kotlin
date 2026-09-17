data class UIntHolder(val value: UInt)
data class UByteHolder(val value: UByte)
data class UShortHolder(val value: UShort)

fun main() {
    println(UInt.MAX_VALUE.hashCode())
    println(2147483648u.hashCode())
    println(200.toUByte().hashCode())
    println(40000.toUShort().hashCode())
    println(1u.hashCode())
    println(ULong.MAX_VALUE.hashCode())

    val anyUInt: Any = UInt.MAX_VALUE
    val anyUByte: Any = 200.toUByte()
    val anyUShort: Any = 40000.toUShort()
    println(anyUInt.hashCode())
    println(anyUByte.hashCode())
    println(anyUShort.hashCode())

    val nullableUInt: UInt? = UInt.MAX_VALUE
    val nullableUByte: UByte? = 200.toUByte()
    val nullableUShort: UShort? = 40000.toUShort()
    println(nullableUInt?.hashCode())
    println(nullableUByte?.hashCode())
    println(nullableUShort?.hashCode())

    println(UIntHolder(UInt.MAX_VALUE).hashCode())
    println(UByteHolder(200.toUByte()).hashCode())
    println(UShortHolder(40000.toUShort()).hashCode())

    val anyUIntHolder: Any = UIntHolder(UInt.MAX_VALUE)
    val anyUByteHolder: Any = UByteHolder(200.toUByte())
    val anyUShortHolder: Any = UShortHolder(40000.toUShort())
    println(anyUIntHolder.hashCode())
    println(anyUByteHolder.hashCode())
    println(anyUShortHolder.hashCode())

    println(listOf(UInt.MAX_VALUE).hashCode())
    println(listOf(200.toUByte()).hashCode())
    println(listOf(40000.toUShort()).hashCode())
}
