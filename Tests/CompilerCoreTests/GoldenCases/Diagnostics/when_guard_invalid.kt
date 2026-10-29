// Kotlin rejects a guard on a comma-separated condition list and any
// guard in a subject-less `when`.

fun commaList(x: Int, c: Boolean): Int {
    return when (x) {
        1, 2 if c -> 1
        else -> 0
    }
}

fun subjectLess(x: Int, c: Boolean): Int {
    return when {
        x > 0 if c -> 1
        else -> 0
    }
}
