@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlinx.cinterop.NativePtr
import kotlin.native.concurrent.AtomicNativePtr

fun atomicNativePtrValue(atomic: AtomicNativePtr): NativePtr = atomic.value

fun atomicNativePtrGetAndSet(atomic: AtomicNativePtr, newValue: NativePtr): NativePtr =
    atomic.getAndSet(newValue)

fun atomicNativePtrCompareAndSet(
    atomic: AtomicNativePtr,
    expected: NativePtr,
    newValue: NativePtr
): Boolean = atomic.compareAndSet(expected, newValue)

fun atomicNativePtrCompareAndSwap(
    atomic: AtomicNativePtr,
    expected: NativePtr,
    newValue: NativePtr
): NativePtr = atomic.compareAndSwap(expected, newValue)

fun atomicNativePtrToString(atomic: AtomicNativePtr): String = atomic.toString()
