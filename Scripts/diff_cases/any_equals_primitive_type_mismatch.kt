// Regression: a local `val`/`var` widened to Any (e.g. `val x: Any = 42L`)
// must box the initializer so its runtime representation carries real type
// info. Comparing two different boxed primitive types with the same bit
// pattern (Int 42 vs Long 42) must never report equal, whether via `==` or
// `.equals()`, and this must hold across reassignment too.
fun takeAny(x: Any): Boolean {
    val list = listOf<Any>(42)
    return list[0] == x
}

fun main() {
    val list = listOf<Any>(42)
    val other: Any = 42L

    println(list[0] is Long)
    println(list[0] == other)
    println(list[0].equals(other))
    println(other == list[0])
    println(other.equals(list[0]))

    var otherVar: Any = 42L
    println(list[0] == otherVar)

    println(takeAny(42L))

    var v: Any = 42
    println(v is Int)
    v = 100L
    println(v is Long)
    println(v == 100)
    println(v == 100L)
}
