package golden.sema

fun useComparator(): Int {
    val cmp = Comparator<Int> { a, b -> a - b }
    return cmp.compare(3, 4)
}
