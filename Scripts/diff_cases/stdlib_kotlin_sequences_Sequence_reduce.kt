fun main() {
    val values: Sequence<Int> = sequenceOf(1, 2, 3, 4)
    println(values.reduce { acc, value -> acc + value })
    println(values.reduceOrNull { acc, value -> acc + value })
    println(values.reduceIndexed { index, acc, value -> acc + index * value })
    println(values.reduceIndexedOrNull { index, acc, value -> acc + index * value })

    val single: Sequence<Int> = sequenceOf(42)
    println(single.reduce { acc, value -> acc + value })
    println(single.reduceOrNull { acc, value -> acc + value })

    val empty: Sequence<Int> = emptySequence()
    println(empty.reduceOrNull { acc, value -> acc + value })
    println(empty.reduceIndexedOrNull { index, acc, value -> acc + index + value })

    // Canonical <S, T : S> signature: the accumulator parameter may widen to a
    // supertype of the element type (acc is Number while elements are Int).
    val widened: Number = values.reduce { acc: Number, value -> value }
    println(widened)
}
