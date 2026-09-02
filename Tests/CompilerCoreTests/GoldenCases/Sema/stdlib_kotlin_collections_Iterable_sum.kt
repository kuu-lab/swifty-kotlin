private fun byteSum(values: Iterable<Byte>): Int = values.sum()
private fun shortSum(values: Iterable<Short>): Int = values.sum()
private fun intSum(values: Iterable<Int>): Int = values.sum()
private fun longSum(values: Iterable<Long>): Long = values.sum()
private fun floatSum(values: Iterable<Float>): Float = values.sum()
private fun doubleSum(values: Iterable<Double>): Double = values.sum()
private fun ubyteSum(values: Iterable<UByte>): UInt = values.sum()
private fun ushortSum(values: Iterable<UShort>): UInt = values.sum()
private fun uintSum(values: Iterable<UInt>): UInt = values.sum()
private fun ulongSum(values: Iterable<ULong>): ULong = values.sum()

private fun sumOfDouble(values: Iterable<String>): Double = values.sumOf { it.length.toDouble() }
private fun sumOfInt(values: Iterable<String>): Int = values.sumOf { it.length }
private fun sumOfLong(values: Iterable<String>): Long = values.sumOf { it.length.toLong() }
private fun sumOfUInt(values: Iterable<String>): UInt = values.sumOf { it.length.toUInt() }
private fun sumOfULong(values: Iterable<String>): ULong = values.sumOf { it.length.toULong() }

fun test(): Int = intSum(emptyList())
