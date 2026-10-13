// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_concurrent_MutableData_n_n.expected.stdout
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.MutableData

fun main() {
    val defaultData = MutableData()
    val explicitData = MutableData(4)
    println(defaultData === explicitData)
}
