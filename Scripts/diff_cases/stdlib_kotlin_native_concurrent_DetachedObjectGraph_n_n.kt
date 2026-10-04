// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs require a Kotlin/Native reference target.
@file:OptIn(
    kotlin.native.concurrent.ObsoleteWorkersApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)
@file:Suppress("DEPRECATION_ERROR", "INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlinx.cinterop.COpaquePointer
import kotlin.native.concurrent.DetachedObjectGraph
import kotlin.native.concurrent.TransferMode

fun detachedObjectGraphFromProducer(): DetachedObjectGraph<String> =
    DetachedObjectGraph { "value" }

fun detachedObjectGraphFromProducerWithMode(): DetachedObjectGraph<String> =
    DetachedObjectGraph(TransferMode.UNSAFE) { "value" }

fun detachedObjectGraphFromPointer(pointer: COpaquePointer?): DetachedObjectGraph<String> =
    DetachedObjectGraph(pointer)

fun main() {}
