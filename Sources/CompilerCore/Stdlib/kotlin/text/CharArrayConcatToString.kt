package kotlin.text

/** Concatenates the characters in the half-open range [startIndex, endIndex). */
@SinceKotlin("1.4")
public fun CharArray.concatToString(startIndex: Int, endIndex: Int): String {
    if (startIndex < 0 || endIndex > this.size) throw IndexOutOfBoundsException()
    if (startIndex > endIndex) throw IllegalArgumentException()

    val result = CharArray(endIndex - startIndex)
    var index = startIndex
    while (index < endIndex) {
        result[index - startIndex] = this[index]
        index++
    }
    return result.concatToString()
}
