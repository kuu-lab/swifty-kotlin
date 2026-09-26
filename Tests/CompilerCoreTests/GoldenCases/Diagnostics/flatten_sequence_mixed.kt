// KUU-461 / BUG-237: mixed List/Sequence element inference. Both compilers
// infer sequenceOf(listOf(1, 2), sequenceOf(3, 4)) as Sequence<Any>
// (Sequence does not inherit Iterable, so the common supertype is Any).
// kotlinc then rejects .flatten() because the element type satisfies neither
// the Sequence<Iterable<T>> nor the Sequence<Sequence<T>> overload
// constraint; KSwiftK must reject it too rather than binding loosely.

fun flattenMixed() {
    val mixed = sequenceOf(listOf(1, 2), sequenceOf(3, 4))
    val flattened = mixed.flatten()
    val checked: Sequence<Any> = flattened
}
