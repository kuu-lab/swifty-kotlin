interface Transformer<A, B> { fun apply(a: A): B }
class Doubler : Transformer<Int, Int> { override fun apply(a: Int) = a * 2 }
fun main() {
    val t: Transformer<Int, Int> = Doubler()
    println(listOf(1, 2).map(t::apply))
    val d = Doubler()
    println(listOf(3, 4).map(d::apply))
    val f: (Int) -> Int = t::apply
    println(f(5))
}
