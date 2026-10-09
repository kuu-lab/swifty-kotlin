private fun doubleSum(values: Sequence<Double>): Double = values.sum()
private fun floatSum(values: Sequence<Float>): Float = values.sum()
private fun longSum(values: Sequence<Long>): Long = values.sum()
private fun ubyteSum(values: Sequence<UByte>): UInt = values.sum()
private fun ushortSum(values: Sequence<UShort>): UInt = values.sum()
private fun uintSum(values: Sequence<UInt>): UInt = values.sum()
private fun ulongSum(values: Sequence<ULong>): ULong = values.sum()

private fun intSum(values: Sequence<Int>): Int = values.sum()

private fun sumOfInt(values: Sequence<String>): Int = values.sumOf { it.length }
private fun sumOfDouble(values: Sequence<String>): Double = values.sumOf { it.length.toDouble() }
private fun sumOfLong(values: Sequence<String>): Long = values.sumOf { it.length.toLong() }
private fun sumOfUInt(values: Sequence<String>): UInt = values.sumOf { it.length.toUInt() }
private fun sumOfULong(values: Sequence<String>): ULong = values.sumOf { it.length.toULong() }

fun test(): Int = intSum(sequenceOf(1, 2))
