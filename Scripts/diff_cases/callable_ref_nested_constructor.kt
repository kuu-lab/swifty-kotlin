class Outer {
    class Nested(val n: Int)
}

fun main() {
    val ctor: (Int) -> Outer.Nested = Outer::Nested
    println(ctor(7).n)
    // Member access on the mapped elements (`nested[0].n`) hits a separate
    // HOF result-type inference gap that also affects `map(::topLevelFactory)`.
    val nested = listOf(1, 2).map(Outer::Nested)
    println(nested.size)
}
