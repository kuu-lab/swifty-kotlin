// Enum entries are constructed once, on first access to the enum class:
// constructor arguments are evaluated a single time and then read back.
var counter = 0
fun next(): Int { counter++; return counter }

enum class E(val id: Int) { A(next()), B(next()) }

enum class Boxed(val items: List<Int>) { ONE(listOf(1)), TWO(listOf(2, 2)) }

fun main() {
    println("before $counter")
    println(E.A.id)
    println(E.A.id)
    println(E.B.id)
    println(counter)
    println(Boxed.ONE.items === Boxed.ONE.items)
    println(Boxed.TWO.items.size)
}
