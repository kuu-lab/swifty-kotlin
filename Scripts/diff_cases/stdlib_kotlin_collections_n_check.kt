// DIFF_CANDIDATE_ONLY: JVM kotlinc cannot call these @PublishedApi internal functions from an ordinary consumer module.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_collections_n_check.expected
// Keep this on the prebuilt stdlib path; source mode re-optimizes the full bundled stdlib for every case.
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

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
