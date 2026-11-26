package kotlin

@PublishedApi
internal inline fun UByte(data: Byte): UByte = data.toInt().toUByte()

@PublishedApi
internal inline fun UShort(data: Short): UShort = data.toInt().toUShort()

@PublishedApi
internal inline fun UInt(data: Int): UInt = data.toUInt()

@PublishedApi
internal inline fun ULong(data: Long): ULong = data.toULong()
