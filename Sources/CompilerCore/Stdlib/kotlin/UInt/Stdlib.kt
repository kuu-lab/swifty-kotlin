package kotlin

// Kotlin models this value-class constructor as an internal inline constructor.
// Preserve the Int bit pattern through the existing primitive conversion path.
internal inline fun UInt(data: Int): UInt = data.toUInt()
