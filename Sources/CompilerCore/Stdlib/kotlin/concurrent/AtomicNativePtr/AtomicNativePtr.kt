@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

import kotlin.native.internal.NativePtr

@SinceKotlin("1.9")
public class AtomicNativePtr(value: NativePtr) {
    @Volatile
    public var value: NativePtr = value

    public fun getAndSet(newValue: NativePtr): NativePtr {
        val oldValue = value
        value = newValue
        return oldValue
    }

    public fun compareAndSet(expected: NativePtr, newValue: NativePtr): Boolean {
        val oldValue = value
        if (oldValue == expected) {
            value = newValue
            return true
        }
        return false
    }

    public fun compareAndExchange(expected: NativePtr, newValue: NativePtr): NativePtr {
        val oldValue = value
        if (oldValue == expected) {
            value = newValue
        }
        return oldValue
    }

    public override fun toString(): String = value.toString()
}
