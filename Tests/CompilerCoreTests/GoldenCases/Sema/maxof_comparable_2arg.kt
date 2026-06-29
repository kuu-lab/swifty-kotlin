package golden.sema

// STDLIB-COMP-FN-005: maxOf(a: T, b: T): T where T : Comparable<T>
fun pickLargerString(a: String, b: String): String = maxOf(a, b)
