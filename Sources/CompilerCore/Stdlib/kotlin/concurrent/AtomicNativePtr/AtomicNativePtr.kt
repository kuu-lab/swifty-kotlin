@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

import kotlin.native.internal.NativePtr

/**
 * Kotlin source-backed implementation of the legacy `kotlin.concurrent.AtomicNativePtr`.
 *
 * Upstream stores the pointer in a `@Volatile` property and implements the
 * operations through `kotlin.internal` field intrinsics. KSwiftK lowers those
 * intrinsics as plain field reads and writes, so the members keep the same
 * sequential shape as the source-backed `kotlin.native.concurrent` twin.
 */
@SinceKotlin("1.9")
public class AtomicNativePtr(value: NativePtr) {
    @Volatile
    public var value: NativePtr = value

    /** Atomically replaces the value and returns the value observed before the replacement. */
    public fun getAndSet(newValue: NativePtr): NativePtr {
        val oldValue = value
        value = newValue
        return oldValue
    }

    /** Atomically replaces the value when it matches [expected]; comparison is by value. */
    public fun compareAndSet(expected: NativePtr, newValue: NativePtr): Boolean {
        val oldValue = value
        if (oldValue == expected) {
            value = newValue
            return true
        }
        return false
    }

    /** Atomically replaces the value when it matches [expected] and returns the observed value. */
    public fun compareAndExchange(expected: NativePtr, newValue: NativePtr): NativePtr {
        val oldValue = value
        if (oldValue == expected) {
            value = newValue
        }
        return oldValue
    }

    /** Returns the string representation of the current atomic value. */
    public override fun toString(): String = value.toString()
}
