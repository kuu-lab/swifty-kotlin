fun findFirst(values: Iterable<Int>): String? {
    return values.firstNotNullOfOrNull { if (it > 0) it.toString() else null }
}

fun findFirstInList(values: List<Int>): String? {
    val found = values.firstNotNullOfOrNull { if (it % 2 == 0) "even" else null }
    return found
}
