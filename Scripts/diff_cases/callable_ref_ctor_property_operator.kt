class Foo(val n: Int) { override fun toString() = "Foo($n)" }

fun applyInt(op: (Int, Int) -> Int): Int = op(2, 3)
fun intPlus(): (Int, Int) -> Int = Int::plus
fun longTimes(): (Long, Long) -> Long = Long::times

fun main() {
    // 1. Bare `::Foo` is an unbound constructor reference: (Int) -> Foo
    val ctor = ::Foo
    println(ctor(3))
    println(listOf(1, 2).map(::Foo))

    // 2. `String::length` is a package-level extension property, unbound
    // to (String) -> Int
    println(listOf("a", "bb").map(String::length))

    // 3. `Int::plus` / `Int::times` are table-driven primitive operators
    // with no real member symbol, unbound to (Int, Int) -> Int
    println(listOf(1, 2, 3).fold(0, Int::plus))
    println(listOf(1, 2, 3).reduce(Int::times))

    val plus: (Int, Int) -> Int = Int::plus
    val times: (Int, Int) -> Int = Int::times
    println(plus(2, 3))
    println(times(2, 3))
    println(applyInt(Int::plus))
    println(applyInt(Int::times))
    println(intPlus()(2, 3))
    println(longTimes()(7L, 6L))
    println(listOf(1L, 2L, 3L).fold(0L, Long::plus))
    println(listOf(1L, 2L, 3L).reduce(Long::times))
}
