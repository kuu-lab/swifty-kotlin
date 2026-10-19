@file:OptIn(
    kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)

package kotlin.concurrent.atomics

import kotlinx.cinterop.NativePtr
import kotlin.concurrent.Volatile

@SinceKotlin("2.1")
@ExperimentalAtomicApi
public class AtomicNativePtr(value: NativePtr) {
    @Volatile
    public var value: NativePtr = value
}
