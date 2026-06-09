package golden.sema

// STDLIB-COMP-FN-029: minOf(a: T, b: T): T where T : Comparable<T>
fun pickSmallerString(a: String, b: String): String = minOf(a, b)
