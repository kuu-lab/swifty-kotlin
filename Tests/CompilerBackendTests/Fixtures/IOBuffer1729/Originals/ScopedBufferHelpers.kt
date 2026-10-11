@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package kotlinx.io

import kotlin.test.assertEquals

fun segmentSizes(buffer: Buffer): List<Int> {
    var segment: Segment? = buffer.head ?: return emptyList()

    val sizes = mutableListOf(segment!!.limit - segment.pos)
    segment = segment.next
    while (segment != null) {
        sizes.add(segment.limit - segment.pos)
        segment = segment.next
    }
    return sizes
}

private fun fromHexChar(char: Char): Int {
    val code = char.code
    return when (code) {
        in '0'.code..'9'.code -> code - '0'.code
        in 'a'.code..'f'.code -> code - 'a'.code + 10
        in 'A'.code..'F'.code -> code - 'A'.code + 10
        else -> throw NumberFormatException("Not a hexadecimal digit: $char")
    }
}

fun String.decodeHex(): ByteArray {
    if (length % 2 != 0) throw IllegalArgumentException("Even number of bytes is expected.")

    val result = ByteArray(length / 2)

    for (idx in result.indices) {
        val byte = fromHexChar(this[idx * 2]).shl(4).or(fromHexChar(this[idx * 2 + 1]))
        result[idx] = byte.toByte()
    }

    return result
}

fun Char.repeat(count: Int): String {
    return toString().repeat(count)
}

fun assertArrayEquals(a: ByteArray, b: ByteArray) {
    assertEquals(a.contentToString(), b.contentToString())
}
