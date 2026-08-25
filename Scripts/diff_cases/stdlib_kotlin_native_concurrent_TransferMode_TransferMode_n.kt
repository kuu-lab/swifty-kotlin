// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.TransferMode

fun main() {
    println(TransferMode.entries.size)
    println(TransferMode.SAFE.value)
    println(TransferMode.valueOf("UNSAFE").value)
    println(TransferMode.values().size)
}
