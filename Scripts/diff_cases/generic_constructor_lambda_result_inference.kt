data class Tuple2<A, B>(val a: A, val b: B)
data class Tuple3<A, B, C>(val a: A, val b: B, val c: C)

class Parser<T>

class AndCombinator<out R>(
    val consumersImpl: List<Any?>,
    val transform: (List<Any?>) -> R
)

inline fun <reified A, reified B, reified C>
    AndCombinator<Tuple2<A, B>>.and(p3: Parser<C>) =
    AndCombinator(consumersImpl + p3, {
        Tuple3(it[0] as A, it[1] as B, it[2] as C)
    })

fun main() {
    val input = AndCombinator<Tuple2<Int, String>>(
        emptyList(),
        { values -> Tuple2(values[0] as Int, values[1] as String) }
    )
    val combined = input.and(Parser<Boolean>())
    val tuple = combined.transform(listOf(1, "two", true))
    println("${tuple.a}:${tuple.b}:${tuple.c}")
}
