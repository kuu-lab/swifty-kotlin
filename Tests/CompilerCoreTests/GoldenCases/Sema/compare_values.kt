package golden.sema

fun compareInts(a: Int, b: Int): Int = compareValues(a, b)
fun compareStrings(a: String, b: String): Int = compareValues(a, b)
fun compareNullableInts(a: Int?, b: Int?): Int = compareValues(a, b)
