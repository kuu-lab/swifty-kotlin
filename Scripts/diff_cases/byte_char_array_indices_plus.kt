private fun checkBytes(values: ByteArray) {
    val indices: IntRange = values.indices
    println("bytes:${values.size}:${indices.first}:${indices.last}:${values.lastIndex}")
    var count = 0
    for (i in values.indices) {
        println("$i:${values[i]}")
        count++
    }
    println("count:$count")
}

private fun checkChars(values: CharArray) {
    val indices: IntRange = values.indices
    println("chars:${values.size}:${indices.first}:${indices.last}:${values.lastIndex}")
    var count = 0
    for (i in values.indices) {
        println("$i:${values[i].code}")
        count++
    }
    println("count:$count")
}

private fun encodeHex(data: ByteArray): String {
    val digits = "0123456789abcdef"
    val chars = CharArray(data.size * 2)
    for (i in data.indices) {
        val value = data[i].toInt() and 255
        chars[i * 2] = digits[value shr 4]
        chars[i * 2 + 1] = digits[value and 15]
    }
    for (i in chars.indices) {
        check(chars[i] != '\u0000')
    }
    return chars.concatToString()
}

private fun checkConcatenation() {
    val left = byteArrayOf(-128, -1, 0)
    val right = byteArrayOf(1, 127)
    val combined: ByteArray = left + right
    println(combined.contentToString())
    println(left.plus(right).contentToString())
    println((byteArrayOf() + right).contentToString())
    println((left + byteArrayOf()).contentToString())
    println((byteArrayOf() + byteArrayOf()).contentToString())
    println((left + left).contentToString())
    println(encodeHex(combined))
    combined[0] = 42.toByte()
    combined[left.size] = 43.toByte()
    val copiedLeft = left + byteArrayOf()
    val copiedRight = byteArrayOf() + right
    copiedLeft[0] = 44.toByte()
    copiedRight[0] = 45.toByte()
    val self = left + left
    self[0] = 46.toByte()
    println(self[left.size])
    println(left.contentToString())
    println(right.contentToString())
}

fun main() {
    checkBytes(byteArrayOf())
    checkBytes(byteArrayOf(127))
    checkBytes(byteArrayOf(-128, -1, 0))
    checkBytes(ByteArray(256) { (it - 128).toByte() })
    checkChars(charArrayOf())
    checkChars(charArrayOf('a'))
    checkChars(charArrayOf('\u0000', 'a', '\uFFFF'))
    checkConcatenation()
    println(encodeHex(ByteArray(256) { it.toByte() }))
}
