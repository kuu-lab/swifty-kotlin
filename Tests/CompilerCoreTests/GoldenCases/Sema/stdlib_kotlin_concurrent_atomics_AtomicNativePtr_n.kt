@file:OptIn(
    kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)

package golden.sema

import kotlin.concurrent.atomics.AtomicNativePtr
import kotlinx.cinterop.NativePtr

fun atomicNativePtrFetchAndUpdate(
    atomic: AtomicNativePtr,
    transform: (NativePtr) -> NativePtr
): NativePtr = atomic.fetchAndUpdate(transform)

fun atomicNativePtrUpdate(
    atomic: AtomicNativePtr,
    transform: (NativePtr) -> NativePtr
): Unit = atomic.update(transform)

fun atomicNativePtrUpdateAndFetch(
    atomic: AtomicNativePtr,
    transform: (NativePtr) -> NativePtr
): NativePtr = atomic.updateAndFetch(transform)
