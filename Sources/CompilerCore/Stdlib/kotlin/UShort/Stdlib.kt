package kotlin

@PublishedApi
internal inline fun UShort(value: Short): UShort = value.toInt().toUShort()
