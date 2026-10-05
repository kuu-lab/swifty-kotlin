private fun checkByte() {
    val source = byteArrayOf(-128, 127)
    val other = byteArrayOf(2.toByte(), (-1).toByte())
    val collection: Collection<Byte> = listOf(2.toByte(), (-1).toByte())
    println((source + 2.toByte()).contentToString())
    println((source + other).contentToString())
    println((source + collection).contentToString())
    println(source.plus(2.toByte()).contentToString())
    println(source.plus(other).contentToString())
    println(source.plus(collection).contentToString())
    println((byteArrayOf() + 2.toByte()).contentToString())
    println((byteArrayOf() + other).contentToString())
    println((byteArrayOf() + collection).contentToString())
    val emptyArrayResult = source + byteArrayOf()
    val emptyCollectionResult = source + emptyList<Byte>()
    emptyArrayResult[0] = 2.toByte()
    emptyCollectionResult[0] = 2.toByte()
    val selfResult = source + source
    selfResult[0] = 2.toByte()
    println(emptyArrayResult.contentToString())
    println(emptyCollectionResult.contentToString())
    println(selfResult.contentToString())
    println(source.contentToString())
    println(other.contentToString())
}

private fun checkShort() {
    val source = shortArrayOf(-32768, 32767)
    val other = shortArrayOf(2.toShort(), (-1).toShort())
    val collection: Collection<Short> = listOf(2.toShort(), (-1).toShort())
    println((source + 2.toShort()).contentToString())
    println((source + other).contentToString())
    println((source + collection).contentToString())
    println(source.plus(2.toShort()).contentToString())
    println(source.plus(other).contentToString())
    println(source.plus(collection).contentToString())
    println((shortArrayOf() + 2.toShort()).contentToString())
    println((shortArrayOf() + other).contentToString())
    println((shortArrayOf() + collection).contentToString())
    val emptyArrayResult = source + shortArrayOf()
    val emptyCollectionResult = source + emptyList<Short>()
    emptyArrayResult[0] = 2.toShort()
    emptyCollectionResult[0] = 2.toShort()
    val selfResult = source + source
    selfResult[0] = 2.toShort()
    println(emptyArrayResult.contentToString())
    println(emptyCollectionResult.contentToString())
    println(selfResult.contentToString())
    println(source.contentToString())
    println(other.contentToString())
}

private fun checkInt() {
    val source = intArrayOf(-1, 3)
    val other = intArrayOf(2, 4)
    val collection: Collection<Int> = listOf(2, 4)
    println((source + 2).contentToString())
    println((source + other).contentToString())
    println((source + collection).contentToString())
    println(source.plus(2).contentToString())
    println(source.plus(other).contentToString())
    println(source.plus(collection).contentToString())
    println((intArrayOf() + 2).contentToString())
    println((intArrayOf() + other).contentToString())
    println((intArrayOf() + collection).contentToString())
    val emptyArrayResult = source + intArrayOf()
    val emptyCollectionResult = source + emptyList<Int>()
    emptyArrayResult[0] = 2
    emptyCollectionResult[0] = 2
    val selfResult = source + source
    selfResult[0] = 2
    println(emptyArrayResult.contentToString())
    println(emptyCollectionResult.contentToString())
    println(selfResult.contentToString())
    println(source.contentToString())
    println(other.contentToString())
}

private fun checkLong() {
    val source = longArrayOf(9007199254740993L, -3L)
    val other = longArrayOf(2L, 4L)
    val collection: Collection<Long> = listOf(2L, 4L)
    println((source + 2L).contentToString())
    println((source + other).contentToString())
    println((source + collection).contentToString())
    println(source.plus(2L).contentToString())
    println(source.plus(other).contentToString())
    println(source.plus(collection).contentToString())
    println((longArrayOf() + 2L).contentToString())
    println((longArrayOf() + other).contentToString())
    println((longArrayOf() + collection).contentToString())
    val emptyArrayResult = source + longArrayOf()
    val emptyCollectionResult = source + emptyList<Long>()
    emptyArrayResult[0] = 2L
    emptyCollectionResult[0] = 2L
    val selfResult = source + source
    selfResult[0] = 2L
    println(emptyArrayResult.contentToString())
    println(emptyCollectionResult.contentToString())
    println(selfResult.contentToString())
    println(source.contentToString())
    println(other.contentToString())
}

private fun checkFloat() {
    val source = floatArrayOf(-0.0f, 1.25f)
    val other = floatArrayOf(2.5f, -4.75f)
    val collection: Collection<Float> = listOf(2.5f, -4.75f)
    println((source + 2.5f).contentToString())
    println((source + other).contentToString())
    println((source + collection).contentToString())
    println(source.plus(2.5f).contentToString())
    println(source.plus(other).contentToString())
    println(source.plus(collection).contentToString())
    println((floatArrayOf() + 2.5f).contentToString())
    println((floatArrayOf() + other).contentToString())
    println((floatArrayOf() + collection).contentToString())
    val emptyArrayResult = source + floatArrayOf()
    val emptyCollectionResult = source + emptyList<Float>()
    emptyArrayResult[0] = 2.5f
    emptyCollectionResult[0] = 2.5f
    val selfResult = source + source
    selfResult[0] = 2.5f
    println(emptyArrayResult.contentToString())
    println(emptyCollectionResult.contentToString())
    println(selfResult.contentToString())
    println(source.contentToString())
    println(other.contentToString())
}

private fun checkDouble() {
    val source = doubleArrayOf(-0.0, 1.25)
    val other = doubleArrayOf(2.5, -4.75)
    val collection: Collection<Double> = listOf(2.5, -4.75)
    println((source + 2.5).contentToString())
    println((source + other).contentToString())
    println((source + collection).contentToString())
    println(source.plus(2.5).contentToString())
    println(source.plus(other).contentToString())
    println(source.plus(collection).contentToString())
    println((doubleArrayOf() + 2.5).contentToString())
    println((doubleArrayOf() + other).contentToString())
    println((doubleArrayOf() + collection).contentToString())
    val emptyArrayResult = source + doubleArrayOf()
    val emptyCollectionResult = source + emptyList<Double>()
    emptyArrayResult[0] = 2.5
    emptyCollectionResult[0] = 2.5
    val selfResult = source + source
    selfResult[0] = 2.5
    println(emptyArrayResult.contentToString())
    println(emptyCollectionResult.contentToString())
    println(selfResult.contentToString())
    println(source.contentToString())
    println(other.contentToString())
}

private fun checkChar() {
    val source = charArrayOf('a', '\uFFFF')
    val other = charArrayOf('b', '\u0000')
    val collection: Collection<Char> = listOf('b', '\u0000')
    println((source + 'b').contentToString())
    println((source + other).contentToString())
    println((source + collection).contentToString())
    println(source.plus('b').contentToString())
    println(source.plus(other).contentToString())
    println(source.plus(collection).contentToString())
    println((charArrayOf() + 'b').contentToString())
    println((charArrayOf() + other).contentToString())
    println((charArrayOf() + collection).contentToString())
    val emptyArrayResult = source + charArrayOf()
    val emptyCollectionResult = source + emptyList<Char>()
    emptyArrayResult[0] = 'b'
    emptyCollectionResult[0] = 'b'
    val selfResult = source + source
    selfResult[0] = 'b'
    println(emptyArrayResult.contentToString())
    println(emptyCollectionResult.contentToString())
    println(selfResult.contentToString())
    println(source.contentToString())
    println(other.contentToString())
}

private fun checkBoolean() {
    val source = booleanArrayOf(true, false)
    val other = booleanArrayOf(false, true)
    val collection: Collection<Boolean> = listOf(false, true)
    println((source + false).contentToString())
    println((source + other).contentToString())
    println((source + collection).contentToString())
    println(source.plus(false).contentToString())
    println(source.plus(other).contentToString())
    println(source.plus(collection).contentToString())
    println((booleanArrayOf() + false).contentToString())
    println((booleanArrayOf() + other).contentToString())
    println((booleanArrayOf() + collection).contentToString())
    val emptyArrayResult = source + booleanArrayOf()
    val emptyCollectionResult = source + emptyList<Boolean>()
    emptyArrayResult[0] = false
    emptyCollectionResult[0] = false
    val selfResult = source + source
    selfResult[0] = false
    println(emptyArrayResult.contentToString())
    println(emptyCollectionResult.contentToString())
    println(selfResult.contentToString())
    println(source.contentToString())
    println(other.contentToString())
}

fun main() {
    checkByte()
    checkShort()
    checkInt()
    checkLong()
    checkFloat()
    checkDouble()
    checkChar()
    checkBoolean()
}
