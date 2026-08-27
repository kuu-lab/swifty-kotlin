fun countIterable(values: Iterable<Int>): Int {
    return values.count()
}

fun countIterablePredicate(values: Iterable<Int?>): Int {
    return values.count { it == null }
}
