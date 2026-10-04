package kotlin

// KSP-912: Keep the stdlib constructor source-backed while preserving raw Short bits.
@PublishedApi
internal inline fun UShort(value: Short): UShort = value.toInt().toUShort()
