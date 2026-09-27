@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package golden.sema

import kotlin.native.internal.NativePtr
import kotlin.concurrent.AtomicNativePtr

fun atomicNativePtrValue(atomic: AtomicNativePtr): NativePtr = atomic.value

fun atomicNativePtrSetValue(atomic: AtomicNativePtr, newValue: NativePtr): Unit {
    atomic.value = newValue
}

fun atomicNativePtrGetAndSet(atomic: AtomicNativePtr, newValue: NativePtr): NativePtr =
    atomic.getAndSet(newValue)

fun atomicNativePtrCompareAndSet(
    atomic: AtomicNativePtr,
    expected: NativePtr,
    newValue: NativePtr
): Boolean = atomic.compareAndSet(expected, newValue)

fun atomicNativePtrCompareAndExchange(
    atomic: AtomicNativePtr,
    expected: NativePtr,
    newValue: NativePtr
): NativePtr = atomic.compareAndExchange(expected, newValue)

fun atomicNativePtrToString(atomic: AtomicNativePtr): String = atomic.toString()
