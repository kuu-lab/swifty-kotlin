package kotlin

// KSP-903: Preserve the raw Byte bits.
@PublishedApi
internal inline fun UByte(value: Byte): UByte = value.toInt().toUByte()

@ExperimentalUnsignedTypes
public inline fun ubyteArrayOf(vararg elements: UByte): UByteArray {
    val result = UByteArray(elements.size)
    var index = 0
    while (index < elements.size) {
        result[index] = elements[index]
        index++
    }
    return result
}
