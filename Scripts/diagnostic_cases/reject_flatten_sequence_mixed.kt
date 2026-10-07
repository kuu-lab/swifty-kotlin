// EXPECT-REJECT
// KUU-461 / BUG-237: Sequence<Any>.flatten() satisfies neither the
// Sequence<Iterable<T>> nor the Sequence<Sequence<T>> overload constraint.
fun main() {
    val mixed = sequenceOf(listOf(1, 2), sequenceOf(3, 4))
    println(mixed.flatten().toList())
}
