package golden.sema

fun minComparable2(a: String, b: String): String = minOf(a, b)
fun minComparableVararg(a: String, b: String, c: String, d: String): String = minOf(a, b, c, d)

fun minByteVararg(a: Byte, b: Byte, c: Byte, d: Byte): Byte = minOf(a, b, c, d)
fun minDoubleVararg(a: Double, b: Double, c: Double, d: Double): Double = minOf(a, b, c, d)
fun minFloatVararg(a: Float, b: Float, c: Float, d: Float): Float = minOf(a, b, c, d)
fun minIntVararg(a: Int, b: Int, c: Int, d: Int): Int = minOf(a, b, c, d)
fun minLongVararg(a: Long, b: Long, c: Long, d: Long): Long = minOf(a, b, c, d)
fun minShortVararg(a: Short, b: Short, c: Short, d: Short): Short = minOf(a, b, c, d)
fun minUByteVararg(a: UByte, b: UByte, c: UByte, d: UByte): UByte = minOf(a, b, c, d)
fun minUIntVararg(a: UInt, b: UInt, c: UInt, d: UInt): UInt = minOf(a, b, c, d)
fun minULongVararg(a: ULong, b: ULong, c: ULong, d: ULong): ULong = minOf(a, b, c, d)
fun minUShortVararg(a: UShort, b: UShort, c: UShort, d: UShort): UShort = minOf(a, b, c, d)

fun minByte2(a: Byte, b: Byte): Byte = minOf(a, b)
fun minShort2(a: Short, b: Short): Short = minOf(a, b)

fun minComparator2(a: Int, b: Int, comparator: Comparator<Int>): Int = minOf(a, b, comparator)
fun minComparatorVararg(a: Int, b: Int, c: Int, d: Int, comparator: Comparator<Int>): Int = minOf(a, b, c, d, comparator = comparator)
fun minComparable3(a: String, b: String, c: String): String = minOf(a, b, c)
fun minByte3(a: Byte, b: Byte, c: Byte): Byte = minOf(a, b, c)
fun minShort3(a: Short, b: Short, c: Short): Short = minOf(a, b, c)
fun minComparator3(a: Int, b: Int, c: Int, comparator: Comparator<Int>): Int = minOf(a, b, c, comparator = comparator)
