// KUU-3862: a statically `Iterable<T>`-typed receiver resolves the
// maxOf/minOf/maxOfOrNull/minOfOrNull selector overloads through the
// collection member fallback, which picked the first registered
// candidate. `Iterable.maxOfOrNull` registers the `(T) -> Double`
// overload before the generic `(T) -> R` one, so `xs.maxOfOrNull { it }`
// bound it and Int selector results were unboxed as Double bits
// (`3.0E-323` / `1.5E-323`). The selector's inferred return type must
// choose the matching overload.
fun main() {
    val xs: Iterable<Int> = listOf(4, 5, 6)
    println(xs.maxOfOrNull { it })
    println(xs.minOfOrNull { it })
    println(xs.maxOf { it })
    println(xs.minOf { it })
    println(xs.maxOfOrNull { it.toDouble() })
    println(xs.minOfOrNull { it.toDouble() })
    println(xs.maxOfOrNull { it.toFloat() })
    println(xs.minOf { it.toFloat() })
    println(xs.maxOfOrNull { "x" })
    println(xs.minOfOrNull { "y" })
    println(xs.maxOf { it * 2 })
    println(listOf(1, 2, 3).asIterable().maxOfOrNull { it })
    println(listOf(1, 2, 3).asIterable().minOfOrNull { it })

    val mutable: MutableIterable<Int> = mutableListOf(3, 1, 2)
    println(mutable.maxOfOrNull { it })
    println(mutable.minOfOrNull { it })

    val strings: Iterable<String> = listOf("b", "a", "c")
    println(strings.maxOfOrNull { it })
    println(strings.minOfOrNull { it })

    val doubles: Iterable<Double> = listOf(4.0, 5.0, 6.0)
    println(doubles.maxOfOrNull { it })

    val intSelector = { x: Int -> x }
    val doubleSelector: (Int) -> Double = { x -> x.toDouble() }
    println(xs.maxOfOrNull(intSelector))
    println(xs.maxOfOrNull(doubleSelector))
}
