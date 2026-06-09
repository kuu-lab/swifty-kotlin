package golden.sema

// STDLIB-COMP-FN-028: maxWithOrNull — List and Sequence member (comparator-based)

fun maxFromList(xs: List<Int>, cmp: Comparator<Int>): Int? = xs.maxWithOrNull(cmp)
fun maxFromSequence(xs: Sequence<Int>, cmp: Comparator<Int>): Int? = xs.maxWithOrNull(cmp)
