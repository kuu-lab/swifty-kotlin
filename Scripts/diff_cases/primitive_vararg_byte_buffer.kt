fun raw(vararg bytes: Byte): ByteArray {
    val result = ByteArray(bytes.size)
    for (i in 0 until bytes.size) result[i] = bytes[i]
    return result
}

fun text(vararg bytes: Byte): String = bytes.decodeToString()

fun main() {
    val bytes = raw(65.toByte(), 66.toByte())
    println(bytes[0])
    println(bytes[1])
    println(bytes.decodeToString())
    println(text(67.toByte(), 68.toByte()))
    println(text(*byteArrayOf(69.toByte(), 70.toByte())))
}
