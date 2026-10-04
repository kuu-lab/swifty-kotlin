package golden.sema

@file:OptIn(
    kotlin.native.concurrent.ObsoleteWorkersApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)
@file:Suppress("DEPRECATION_ERROR", "INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlinx.cinterop.COpaquePointer
import kotlin.concurrent.AtomicNativePtr
import kotlin.native.concurrent.DetachedObjectGraph

fun detachedObjectGraphAsCPointer(graph: DetachedObjectGraph<String>): COpaquePointer? =
    graph.asCPointer()

fun detachedObjectGraphStable(graph: DetachedObjectGraph<String>): AtomicNativePtr =
    graph.stable
