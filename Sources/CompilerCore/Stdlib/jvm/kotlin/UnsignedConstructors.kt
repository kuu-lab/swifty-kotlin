package kotlin

@PublishedApi
internal inline fun UByte(value: Byte): UByte = value.toInt().toUByte()

@PublishedApi
internal inline fun UShort(value: Short): UShort = value.toInt().toUShort()

@PublishedApi
internal inline fun UInt(data: Int): UInt = data.toUInt()

@PublishedApi
internal inline fun ULong(value: Long): ULong = value.toULong()
