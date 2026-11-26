package kotlin

@PublishedApi
internal inline fun UShort(data: Short): UShort = data.toInt().toUShort()
