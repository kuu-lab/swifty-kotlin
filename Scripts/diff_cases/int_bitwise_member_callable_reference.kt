// KUU-4135: `Int::and` / `::or` / `::xor` are bundled `kotlin` package
// extensions (`infix fun Int.and(other: Int): Int` etc. in Numbers.kt), so
// the class-scoped callable reference binds the extension symbol directly —
// the same `(Int, Int) -> Int` shape upstream's member functions give.
val andRef: (Int, Int) -> Int = Int::and
val orRef = Int::or
val xorRef = Int::xor

fun box(): String {
    if (andRef(6, 3) != 2) return "Fail andRef"
    if (orRef(4, 1) != 5) return "Fail orRef"
    if (xorRef(5, 3) != 6) return "Fail xorRef"
    if (Int::and.name != "and") return "Fail and.name"
    if (Int::or.name != "or") return "Fail or.name"
    if (Int::xor.name != "xor") return "Fail xor.name"
    if ((Int::and).let { it(6, 3) } != 2) return "Fail let and"
    if ((Int::or).let { it(4, 1) } != 5) return "Fail let or"
    if ((Int::xor).let { it(5, 3) } != 6) return "Fail let xor"
    return "OK"
}

fun main() {
    println(box())
    println(Int::and.name)
    println(Int::or.name)
    println(Int::xor.name)
    println(andRef(6, 3))
    println(orRef(4, 1))
    println(xorRef(5, 3))
    println((Int::inv)(0))
    println((Int::shl)(1, 4))
    println(listOf(1, 2, 4).fold(0, Int::or))
    println(listOf(7, 3, 1).fold(7, Int::and))
}
