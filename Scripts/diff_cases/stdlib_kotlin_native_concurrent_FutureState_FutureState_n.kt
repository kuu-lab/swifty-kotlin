// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.FutureState

fun main() {
    println(FutureState.entries.size)
    println(FutureState.INVALID.value)
    println(FutureState.SCHEDULED.value)
    println(FutureState.COMPUTED.value)
    println(FutureState.CANCELLED.value)
    println(FutureState.THROWN.value)
    println(FutureState.valueOf("THROWN").value)
    println(FutureState.values().size)
}
