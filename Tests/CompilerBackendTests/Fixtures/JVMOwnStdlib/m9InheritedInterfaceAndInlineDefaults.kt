interface Value { fun value(n: Int = 21): Int }
open class Base { open fun value(n: Int = 20): Int = n }
class Derived: Base() { override fun value(n: Int): Int = n * 2 }
class Direct: Value { override fun value(n: Int): Int = n + 1 }
inline fun calculate(n: Int = 21, block: (Int) -> Int = { it * 2 }): Int = block(n)
inline fun choose(n: Int = 1, block: () -> Int): Int = block() + n
fun early(): Int { choose(block = { return 42 }); return 0 }
fun main() {
    val direct = Direct()
    val value: Value = direct
    println(direct.value())
    println(value.value())
    println(Derived().value())
    println(calculate())
    println(calculate(block = { it + 1 }))
    println(calculate(block = { it * 2 }, n = 10))
    println(early())
}
