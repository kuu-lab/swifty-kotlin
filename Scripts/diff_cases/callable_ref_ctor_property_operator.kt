class Foo(val n: Int) { override fun toString() = "Foo($n)" }

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
}
