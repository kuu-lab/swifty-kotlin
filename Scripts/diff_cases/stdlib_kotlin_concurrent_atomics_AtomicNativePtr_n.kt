// CANDIDATE-ONLY: kotlin.concurrent.atomics is Native-only in Kotlin 2.3.10 and has no JVM kotlinc oracle.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_concurrent_atomics_AtomicNativePtr_n.expected.stdout

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
