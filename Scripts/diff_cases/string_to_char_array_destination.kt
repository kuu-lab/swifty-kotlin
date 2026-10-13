// KUU-1397: String.toCharArray(destination, destinationOffset, startIndex, endIndex).
// kotlin.text String overload (since Kotlin 2.0); the Kotlin 2.3.10 API
// surface has no CharSequence.toCharArray, so receivers stay String.
private fun codesOf(array: CharArray): String {
    val sb = StringBuilder()
    var index = 0
    while (index < array.size) {
        if (index > 0) sb.append(',')
        sb.append(array[index].code)
        index++
    }
    return sb.toString()
}

private fun checkCopy(
    text: String,
    size: Int,
    destinationOffset: Int,
    startIndex: Int,
    endIndex: Int
) {
    val destination = CharArray(size)
    try {
        val result = text.toCharArray(destination, destinationOffset, startIndex, endIndex)
        println(codesOf(result) + "|" + (result === destination))
    } catch (e: IndexOutOfBoundsException) {
        println("IndexOutOfBoundsException")
    } catch (e: IllegalArgumentException) {
        println("IllegalArgumentException")
    }
}

// startIndex > endIndex on the 4-arg overload is contract-ambiguous:
// Kotlin/JVM reports it from String.getChars as IndexOutOfBoundsException
// while Kotlin/Native reports IllegalArgumentException. Only assert that an
// exception is thrown.
private fun checkThrows(
    text: String,
    size: Int,
    destinationOffset: Int,
    startIndex: Int,
    endIndex: Int
) {
    val destination = CharArray(size)
    try {
        text.toCharArray(destination, destinationOffset, startIndex, endIndex)
        println("no-throw")
    } catch (e: Exception) {
        println("thrown")
    }
}

fun main() {
    val dest = CharArray(5)
    val returned = "abc".toCharArray(dest, 1)
    println(returned.toList())
    println(codesOf(dest))
    println(returned === dest)

    println(codesOf("abcdef".toCharArray(CharArray(6))))
    println(codesOf("abcdef".toCharArray(CharArray(8), 2)))
    println(codesOf("abcdef".toCharArray(CharArray(8), 2, 1)))
    println(codesOf("abcdef".toCharArray(CharArray(8), 1, 2, 4)))
    println(codesOf("abcdef".toCharArray(destination = CharArray(4), destinationOffset = 1, startIndex = 1, endIndex = 3)))
    println(codesOf("abcdef".toCharArray(CharArray(8), endIndex = 2)))
    println(codesOf("".toCharArray(CharArray(0))))
    println(codesOf("".toCharArray(CharArray(2), 1)))

    checkCopy("abcdef", 6, 0, 0, 6)
    checkCopy("abcdef", 6, 0, 6, 6)
    checkCopy("abcdef", 6, 6, 0, 0)
    checkCopy("abcdef", 4, 0, -1, 3)
    checkCopy("abcdef", 4, -1, 0, 3)
    checkCopy("abcdef", 4, 0, 0, 7)
    checkCopy("abcdef", 4, 0, 5, 7)
    checkCopy("abcdef", 4, 3, 0, 2)
    checkCopy("abcdef", 4, 2, 0, 2)
    checkCopy("abcdef", 6, -1, 0, 0)
    checkThrows("abcdef", 4, 0, 4, 2)
    checkThrows("abcdef", 4, 0, -2, -1)
}
