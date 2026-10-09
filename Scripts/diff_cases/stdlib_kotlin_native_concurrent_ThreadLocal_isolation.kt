// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_concurrent_ThreadLocal_isolation.expected
// DIFF_CANDIDATE_ONLY
@file:Suppress("DEPRECATION_ERROR")
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.ThreadLocal
import kotlin.native.concurrent.TransferMode
import kotlin.native.concurrent.Worker

@ThreadLocal
var value = 0

fun main() {
    value = 7
    val worker = Worker.start()
    val future = worker.execute(TransferMode.SAFE, { Unit }) {
        val previous = value
        value = 9
        previous
    }
    println(future.result)
    println(value)
    worker.requestTermination(true)
}
