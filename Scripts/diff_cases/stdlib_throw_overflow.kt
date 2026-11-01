// KUU-4116: kotlin.collections.throwCountOverflow / throwIndexOverflow are
// internal stdlib helpers reachable under INVISIBLE_MEMBER/INVISIBLE_REFERENCE
// suppression; both throw ArithmeticException on the JVM.
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

fun countOverflowReturnsUnit(): Unit = kotlin.collections.throwCountOverflow()
fun indexOverflowReturnsUnit(): Unit = kotlin.collections.throwIndexOverflow()

fun main() {
    try {
        kotlin.collections.throwCountOverflow()
    } catch (e: ArithmeticException) {
        println("count threw ArithmeticException: ${e.message}")
    }
    try {
        kotlin.collections.throwIndexOverflow()
    } catch (e: ArithmeticException) {
        println("index threw ArithmeticException: ${e.message}")
    }
    try {
        countOverflowReturnsUnit()
    } catch (e: ArithmeticException) {
        println("wrapped count: ${e.message}")
    }
    try {
        indexOverflowReturnsUnit()
    } catch (e: ArithmeticException) {
        println("wrapped index: ${e.message}")
    }
}
