// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_concurrent_AtomicInt_n_n.expected.stdout

import kotlin.concurrent.AtomicInt

fun main() {
    val atomic = AtomicInt(7)
    println(atomic.value)
    println(atomic.toString())
}
