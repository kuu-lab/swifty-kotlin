// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_concurrent_Future_n_n.expected.stdout
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.Future

fun main() {
    val future: Future<Int>? = null
    println(future == null)
}
