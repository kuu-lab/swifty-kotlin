@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.TransferMode

fun main() {
    println(TransferMode.entries.size)
    println(TransferMode.SAFE.value)
    println(TransferMode.valueOf("UNSAFE").value)
    println(TransferMode.values().size)
}
