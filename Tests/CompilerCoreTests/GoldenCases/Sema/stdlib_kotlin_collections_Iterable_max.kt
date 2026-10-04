package golden.sema

// KSP-983: exact kotlin.collections.Iterable.max-family overloads.

fun iterableMaxComparable(values: Iterable<Int>): Int = values.max()
fun iterableMaxDouble(values: Iterable<Double>): Double = values.max()
fun iterableMaxFloat(values: Iterable<Float>): Float = values.max()
fun iterableMaxBy(values: Iterable<Int>): Int = values.maxBy { it }
fun iterableMaxByOrNull(values: Iterable<Int>): Int? = values.maxByOrNull { it }
fun iterableMaxOfComparable(values: Iterable<Int>): Int = values.maxOf { it }
fun iterableMaxOfDouble(values: Iterable<Int>): Double = values.maxOf { it.toDouble() }
fun iterableMaxOfFloat(values: Iterable<Int>): Float = values.maxOf { it.toFloat() }
fun iterableMaxOfOrNullComparable(values: Iterable<Int>): Int? = values.maxOfOrNull { it }
fun iterableMaxOfOrNullDouble(values: Iterable<Int>): Double? = values.maxOfOrNull { it.toDouble() }
fun iterableMaxOfOrNullFloat(values: Iterable<Int>): Float? = values.maxOfOrNull { it.toFloat() }
fun iterableMaxOfWith(values: Iterable<Int>, comparator: Comparator<Any>): Int = values.maxOfWith(comparator) { it }
fun iterableMaxOfWithOrNull(values: Iterable<Int>, comparator: Comparator<Any>): Int? = values.maxOfWithOrNull(comparator) { it }
fun iterableMaxOrNullComparable(values: Iterable<Int>): Int? = values.maxOrNull()
fun iterableMaxOrNullDouble(values: Iterable<Double>): Double? = values.maxOrNull()
fun iterableMaxOrNullFloat(values: Iterable<Float>): Float? = values.maxOrNull()
fun iterableMaxWith(values: Iterable<Int>, comparator: Comparator<Any>): Int = values.maxWith(comparator)
fun iterableMaxWithOrNull(values: Iterable<Int>, comparator: Comparator<Any>): Int? = values.maxWithOrNull(comparator)
