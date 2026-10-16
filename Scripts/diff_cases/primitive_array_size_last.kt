// KUU-2303: Size-only primitive-array constructors must retain last() element types.
fun lastBoolean(size: Int): Boolean {
    val values = BooleanArray(size + 1)
    return values.last()
}

fun lastByte(size: Int): Byte {
    val values = ByteArray(size + 1)
    return values.last()
}

fun lastShort(size: Int): Short {
    val values = ShortArray(size + 1)
    return values.last()
}

fun lastInt(size: Int): Int {
    val values = IntArray(size + 1)
    return values.last()
}

fun lastLong(size: Int): Long {
    val values = LongArray(size + 1)
    return values.last()
}

fun lastFloat(size: Int): Float {
    val values = FloatArray(size + 1)
    return values.last()
}

fun lastDouble(size: Int): Double {
    val values = DoubleArray(size + 1)
    return values.last()
}

fun lastChar(size: Int): Char {
    val values = CharArray(size + 1)
    return values.last()
}

fun preservedArrayPaths(size: Int): Double {
    val values = DoubleArray(size + 1)
    val initialized = DoubleArray(size + 1) { it.toDouble() }
    return values.first() + (values.lastOrNull() ?: 0.0) + values[0] + values.map { it }.size.toDouble() +
        initialized.last() + IntArray(size + 1).last().toDouble()
}

fun main() {
    println(lastBoolean(1))
    println(lastByte(1))
    println(lastShort(1))
    println(lastInt(1))
    println(lastLong(1))
    println(lastFloat(1))
    println(lastDouble(1))
    println(lastChar(1).code)
    println(preservedArrayPaths(1))
}
