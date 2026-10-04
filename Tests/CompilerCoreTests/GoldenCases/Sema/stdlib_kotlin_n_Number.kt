package golden.sema

fun numberToDouble(n: Number): Double = n.toDouble()
fun numberToFloat(n: Number): Float = n.toFloat()
fun numberToLong(n: Number): Long = n.toLong()
fun numberToInt(n: Number): Int = n.toInt()
fun numberToShort(n: Number): Short = n.toShort()
fun numberToByte(n: Number): Byte = n.toByte()

fun <T : Number> sumOf(a: T, b: T): Double = a.toDouble() + b.toDouble()
