package golden.sema

fun useSorted(values: Iterable<Int>): List<Int> = values.sorted()

fun useSortedBy(values: Iterable<String>): List<String> =
    values.sortedBy { value -> if (value.isEmpty()) null else value }

fun useSortedByDescending(values: Iterable<String>): List<String> =
    values.sortedByDescending { value -> if (value.isEmpty()) null else value }

fun useSortedDescending(values: Iterable<Int>): List<Int> = values.sortedDescending()

fun useSortedWith(values: Iterable<String?>, comparator: Comparator<in String?>): List<String?> =
    values.sortedWith(comparator)
