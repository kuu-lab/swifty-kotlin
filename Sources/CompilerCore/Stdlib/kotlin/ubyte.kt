package kotlin

// KSP-789: Keep the primitive UByteArray factory source-backed.
public inline fun ubyteArrayOf(vararg elements: UByte): UByteArray {
    val result = UByteArray(elements.size)
    var index = 0
    while (index < elements.size) {
        result[index] = elements[index]
        index++
    }
    return result
}
