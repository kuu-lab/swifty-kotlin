@OptIn(ExperimentalUnsignedTypes::class)
fun box(): String {
    val ints = intArrayOf(Int.MAX_VALUE, Int.MIN_VALUE)
    ints[0] += 1
    ints[1] -= 1
    if (ints[0] != Int.MIN_VALUE || ints[1] != Int.MAX_VALUE) {
        return "IntArray wrap failed: ${ints[0]}, ${ints[1]}"
    }

    val uints = uintArrayOf(UInt.MAX_VALUE, 0u)
    uints[0] += 1u
    uints[1] -= 1u
    if (uints[0] != 0u || uints[1] != UInt.MAX_VALUE) {
        return "UIntArray wrap failed: ${uints[0]}, ${uints[1]}"
    }

    val bytes = byteArrayOf(127, -128)
    bytes[0]++
    bytes[1]--
    if (bytes[0] != (-128).toByte() || bytes[1] != 127.toByte()) {
        return "ByteArray wrap failed: ${bytes[0]}, ${bytes[1]}"
    }

    val shorts = shortArrayOf(32767, -32768)
    shorts[0]++
    shorts[1]--
    if (shorts[0] != (-32768).toShort() || shorts[1] != 32767.toShort()) {
        return "ShortArray wrap failed: ${shorts[0]}, ${shorts[1]}"
    }

    val ubytes = ubyteArrayOf(255u, 0u)
    ubytes[0]++
    ubytes[1]--
    if (ubytes[0] != 0u.toUByte() || ubytes[1] != 255u.toUByte()) {
        return "UByteArray wrap failed: ${ubytes[0]}, ${ubytes[1]}"
    }

    val ushorts = ushortArrayOf(65535u, 0u)
    ushorts[0]++
    ushorts[1]--
    if (ushorts[0] != 0u.toUShort() || ushorts[1] != 65535u.toUShort()) {
        return "UShortArray wrap failed: ${ushorts[0]}, ${ushorts[1]}"
    }

    val boxedInts = arrayOf<Int>(Int.MAX_VALUE)
    boxedInts[0] += 1
    if (boxedInts[0] != Int.MIN_VALUE) {
        return "Array<Int> wrap failed: ${boxedInts[0]}"
    }

    val boxedBytes = arrayOf<Byte>(127)
    boxedBytes[0]++
    if (boxedBytes[0] != (-128).toByte()) {
        return "Array<Byte> wrap failed: ${boxedBytes[0]}"
    }

    val byteList = mutableListOf<Byte>(127, -128)
    byteList[0]++
    byteList[1]--
    if (byteList[0] != (-128).toByte() || byteList[1] != 127.toByte()) {
        return "MutableList<Byte> wrap failed: ${byteList[0]}, ${byteList[1]}"
    }

    return "OK"
}

fun main() {
    println(box())
}
