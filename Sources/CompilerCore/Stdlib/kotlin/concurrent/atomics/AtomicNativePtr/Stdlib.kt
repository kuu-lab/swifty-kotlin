@file:OptIn(
    kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)

package kotlin.concurrent.atomics

import kotlinx.cinterop.NativePtr
import kotlin.concurrent.Volatile

/** Stores the native pointer used by the atomic receiver APIs. */
@SinceKotlin("2.1")
@ExperimentalAtomicApi
public class AtomicNativePtr(value: NativePtr) {
    @Volatile
    public var value: NativePtr = value
}
