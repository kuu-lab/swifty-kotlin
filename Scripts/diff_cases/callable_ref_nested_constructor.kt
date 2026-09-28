class Outer {
    class Nested(val n: Int)
}

fun main() {
    val ctor: (Int) -> Outer.Nested = Outer::Nested
    println(ctor(7).n)
    val nested: List<Outer.Nested> = listOf(1, 2).map(Outer::Nested)
    println(nested[0].n + nested[1].n)
}
