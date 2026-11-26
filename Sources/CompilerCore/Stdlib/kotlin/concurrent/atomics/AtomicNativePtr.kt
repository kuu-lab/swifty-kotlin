@file:OptIn(
    kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)

package kotlin.concurrent.atomics

import kotlinx.cinterop.NativePtr

public fun AtomicNativePtr.fetchAndUpdate(transform: (NativePtr) -> NativePtr): NativePtr {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return old
    }
}

public fun AtomicNativePtr.update(transform: (NativePtr) -> NativePtr): Unit {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return
    }
}

public fun AtomicNativePtr.updateAndFetch(transform: (NativePtr) -> NativePtr): NativePtr {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}
