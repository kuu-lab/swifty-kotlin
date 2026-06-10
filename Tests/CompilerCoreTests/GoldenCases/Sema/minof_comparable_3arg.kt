package golden.sema

// STDLIB-COMP-FN-030: minOf(a: T, b: T, c: T): T where T : Comparable<T>
fun minOfComparable3ArgString(a: String, b: String, c: String): String = minOf(a, b, c)
