// DIFF_CANDIDATE_ONLY: Kotlin 2.4.20 kotlin-test.jar does not expose the assertNotNull lazy-message overload.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kotlin_test_null_lazy_notnull_candidate.expected
@file:OptIn(kotlin.test.ExperimentalKotlinTestApi::class)
import kotlin.test.*

fun main() {
    var calls = 0
    val present: String? = "present"
    val result: String = assertNotNull(present, lazyMessage = { calls++; "unused not-null message" })
    println(result)
    println(calls)

    try {
        assertNotNull<String>(null, lazyMessage = { calls++; "lazy not-null message" })
    } catch (e: AssertionError) {
        println(e.message)
    }
    println(calls)
}
