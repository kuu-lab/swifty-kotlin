data class P(val n: String, val a: Int, val c: Int, val d: Int)

fun name(p: P): String = p.n

fun main() {
    val a = P("a", 1, 1, 1)
    val b = P("a", 2, 1, 1)
    val c = P("a", 1, 2, 1)
    val d = P("a", 1, 1, 2)

    println(compareValuesBy(a, b, { it.n }, { it.a }))
    println(compareValuesBy(b, a, { it.n }, { it.a }))
    println(compareValuesBy(a, a, { it.n }, { it.a }))
    println(compareValuesBy(a, c, { it.n }, { it.a }, { it.c }))
    println(compareValuesBy(a, d, { it.n }, { it.a }, { it.c }, { it.d }))
    println(compareValuesBy(d, a, { it.n }, { it.a }, { it.c }, { it.d }))
    println(compareValuesBy(a, a, { it.n }, { it.a }, { it.c }, { it.d }))

    println(compareValuesBy(a, b, ::name, { it.a }))
    val selector: (P) -> Comparable<*>? = { it.n }
    println(compareValuesBy(a, b, selector, { it.a }))
    println(compareValuesBy<P>(a, b, { it.n }, { it.a }))
    println(compareValuesBy(a, b) { it.a })
    println(compareValuesBy(a, b, reverseOrder<Int>(), { it.a }))
    val comparator = naturalOrder<Int>()
    println(compareValuesBy(a, b, comparator) { it.a })

    println(compareValuesBy("ab", "cd", { it.length }, { it }))
    println(compareValuesBy(a, b, { null }, { it.a }))

    var calls = 0
    println(compareValuesBy(a, b, { it.a }, { calls++; it.c }))
    println(calls)
    println(compareValuesBy(a, c, { it.a }, { it.c }, { calls++; it.d }))
    println(calls)
    println(compareValuesBy(a, d, { it.n }, { it.a }, { it.d }, { calls++; it.c }))
    println(calls)
}
