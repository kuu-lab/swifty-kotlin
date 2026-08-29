// SKIP-DIFF (KSP-959): the helpers are internal @PublishedApi stdlib APIs.
// Run this candidate directly with kswiftc; reference kotlinc requires friend access.
package kotlin.collections

private fun countOverflowMessage(): String = try {
    throwCountOverflow()
    "no throw"
} catch (e: ArithmeticException) {
    e.message ?: "null"
}

private fun indexOverflowMessage(): String = try {
    throwIndexOverflow()
    "no throw"
} catch (e: ArithmeticException) {
    e.message ?: "null"
}

fun main() {
    println(countOverflowMessage())
    println(indexOverflowMessage())
    println(countOverflowMessage() == "Count overflow has happened.")
    println(indexOverflowMessage() == "Index overflow has happened.")
}
