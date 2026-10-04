package golden.sema

fun charSequenceMin(source: CharSequence): Char = source.min()

fun charSequenceMinBy(source: CharSequence): Char = source.minBy { it.code }

fun charSequenceMinByOrNull(source: CharSequence): Char? =
    source.minByOrNull { it.code }

fun charSequenceMinOfDouble(source: CharSequence): Double =
    source.minOf { it.code.toDouble() }

fun charSequenceMinOfFloat(source: CharSequence): Float =
    source.minOf { it.code.toFloat() }

fun charSequenceMinOfComparable(source: CharSequence): Int =
    source.minOf { it.code }

fun charSequenceMinOfOrNullDouble(source: CharSequence): Double? =
    source.minOfOrNull { it.code.toDouble() }

fun charSequenceMinOfOrNullFloat(source: CharSequence): Float? =
    source.minOfOrNull { it.code.toFloat() }

fun charSequenceMinOfOrNullComparable(source: CharSequence): Int? =
    source.minOfOrNull { it.code }

fun charSequenceMinOfWith(source: CharSequence, comparator: Comparator<Int>): Int =
    source.minOfWith(comparator) { it.code }

fun charSequenceMinOfWithOrNull(source: CharSequence, comparator: Comparator<Int>): Int? =
    source.minOfWithOrNull(comparator) { it.code }

fun charSequenceMinOrNull(source: CharSequence): Char? = source.minOrNull()

fun charSequenceMinWith(source: CharSequence, comparator: Comparator<Char>): Char =
    source.minWith(comparator)

fun charSequenceMinWithOrNull(source: CharSequence, comparator: Comparator<Char>): Char? =
    source.minWithOrNull(comparator)

fun stringMin(source: String): Char = source.min()

fun stringBuilderMinOrNull(source: StringBuilder): Char? = source.minOrNull()
