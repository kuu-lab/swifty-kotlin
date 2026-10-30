// KUU-3819: Map.values is a MutableCollection and resolves Iterable extrema
// through the collection member fallback. Arity-first candidate selection
// bound maxOrNull() to the bundled Iterable<Double> overload, which threw
// ClassCastException unboxing Int elements as Double. Element-type-aware
// candidate selection must pick the generic Comparable overload instead.
fun main() {
    val values = mapOf(1 to 11, 2 to 12).values
    println(values.minOrNull())
    println(values.maxOrNull())

    val mutable: MutableCollection<Int> = mutableListOf(3, 1, 2)
    println(mutable.minOrNull())
    println(mutable.maxOrNull())

    val doubles: MutableCollection<Double> = mutableListOf(1.5, 2.5)
    println(doubles.minOrNull())
    println(doubles.maxOrNull())

    val empty: Collection<Int> = listOf()
    println(empty.maxOrNull())
}
