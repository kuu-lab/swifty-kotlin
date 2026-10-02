// `Int.toString()` and `Int.toString(radix)` both exist; the overload is
// chosen by the expected function type's arity.
fun main() {
    val toS: (Int) -> String = Int::toString
    println(toS(42))
    println(listOf(1, 2).map(Int::toString))
    val toL: (Long) -> String = Long::toString
    println(toL(7L))
    println(listOf(3L, 4L).map(Long::toString))
    val radix: (Int, Int) -> String = Int::toString
    println(radix(255, 16))
    val toB: (Boolean) -> String = Boolean::toString
    println(toB(true))
}
