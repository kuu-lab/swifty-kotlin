// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent.atomics is Native-only
// in Kotlin 2.3.10 and is unavailable in the JVM kotlinc reference environment.

@file:OptIn(
    kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)

import kotlin.concurrent.atomics.AtomicNativePtr
import kotlinx.cinterop.NativePtr

fun fetchAndUpdate(atomic: AtomicNativePtr, transform: (NativePtr) -> NativePtr): NativePtr =
    atomic.fetchAndUpdate(transform)

fun update(atomic: AtomicNativePtr, transform: (NativePtr) -> NativePtr): Unit =
    atomic.update(transform)

fun updateAndFetch(atomic: AtomicNativePtr, transform: (NativePtr) -> NativePtr): NativePtr =
    atomic.updateAndFetch(transform)

fun main() {}
