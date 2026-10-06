// KUU-620: Sequence<Iterable<T>>.flatten() must resolve to the dedicated
// Sequence<Iterable<T>> overload and return Sequence<T>.

fun flattenIterables(lists: Sequence<List<Int>>) {
    val flattened = lists.flatten()
    val checked: Sequence<Int> = flattened
}

fun flattenIterableParams(lists: Sequence<Iterable<Int>>) {
    val flattened = lists.flatten()
    val checked: Sequence<Int> = flattened
}
