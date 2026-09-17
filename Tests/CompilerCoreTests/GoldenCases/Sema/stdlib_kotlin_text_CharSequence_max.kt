package golden.sema

// KSP-1387: exact kotlin.text.CharSequence.max-family overloads.

fun charSequenceMax(source: CharSequence): Char = source.max()
fun charSequenceMaxBy(source: CharSequence): Char = source.maxBy { it.code }
fun charSequenceMaxByOrNull(source: CharSequence): Char? = source.maxByOrNull { it.code }
fun charSequenceMaxOfDouble(source: CharSequence): Double = source.maxOf { it.code.toDouble() }
fun charSequenceMaxOfFloat(source: CharSequence): Float = source.maxOf { it.code.toFloat() }
fun charSequenceMaxOfComparable(source: CharSequence): Int = source.maxOf { it.code }
fun charSequenceMaxOfOrNullDouble(source: CharSequence): Double? = source.maxOfOrNull { it.code.toDouble() }
fun charSequenceMaxOfOrNullFloat(source: CharSequence): Float? = source.maxOfOrNull { it.code.toFloat() }
fun charSequenceMaxOfOrNullComparable(source: CharSequence): Int? = source.maxOfOrNull { it.code }
fun charSequenceMaxOfWith(source: CharSequence, comparator: Comparator<Any>): Int =
    source.maxOfWith(comparator) { it.code }
fun charSequenceMaxOfWithOrNull(source: CharSequence, comparator: Comparator<Any>): Int? =
    source.maxOfWithOrNull(comparator) { it.code }
fun charSequenceMaxOrNull(source: CharSequence): Char? = source.maxOrNull()
fun charSequenceMaxWith(source: CharSequence, comparator: Comparator<Char>): Char =
    source.maxWith(comparator)
fun charSequenceMaxWithOrNull(source: CharSequence, comparator: Comparator<Char>): Char? =
    source.maxWithOrNull(comparator)
