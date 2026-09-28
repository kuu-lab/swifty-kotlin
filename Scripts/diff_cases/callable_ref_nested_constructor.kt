class Outer {
    class Nested(val n: Int)
}

fun main() {
    val ctor: (Int) -> Outer.Nested = Outer::Nested
    println(ctor(7).n)
    println(listOf(1, 2).map(Outer::Nested).map { it.n })
}
