// Regression: destructuring for-in over Iterable.withIndex() produces
// IndexedValue entries (not Pair) and dispatches through the IndexingIterable
// runtime bridge instead of treating the result as a List.
fun main() {
    val indexed = listOf("a", "b", "c").withIndex()
    for ((i, v) in indexed) {
        println("$i: $v")
    }
}
