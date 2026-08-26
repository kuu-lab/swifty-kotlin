// SKIP-DIFF (DEBT-DIFF-001): JVM kotlinc keeps these @PublishedApi internal
// functions inaccessible to an ordinary consumer module. The candidate-only
// case is executed directly with kswiftc; the same behavior was checked with
// kotlinc using -Xfriend-paths and the reference kotlin-stdlib jar.

fun main() {
    val values = intArrayOf(Int.MIN_VALUE, -1, 0, 1, Int.MAX_VALUE)
    for (value in values) {
        for (kind in arrayOf("index", "count")) {
            try {
                val result = if (kind == "index") {
                    kotlin.collections.checkIndexOverflow(value)
                } else {
                    kotlin.collections.checkCountOverflow(value)
                }
                println("$kind:$value -> value:$result")
            } catch (e: ArithmeticException) {
                println("$kind:$value -> ArithmeticException:${e.message}")
            }
        }
    }
}
