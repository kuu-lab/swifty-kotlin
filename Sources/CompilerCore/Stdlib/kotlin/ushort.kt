package kotlin

@ExperimentalUnsignedTypes
public inline fun ushortArrayOf(vararg elements: UShort): UShortArray {
    val result = UShortArray(elements.size)
    var index = 0
    while (index < elements.size) {
        result[index] = elements[index]
        index++
    }
    return result
}
