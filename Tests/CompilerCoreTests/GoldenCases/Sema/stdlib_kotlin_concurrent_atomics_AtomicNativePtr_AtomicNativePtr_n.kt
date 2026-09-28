@file:OptIn(
    kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)

package golden.sema

import kotlin.concurrent.atomics.AtomicNativePtr
import kotlinx.cinterop.NativePtr

fun atomicNativePtrReceiverMembers(
    atomic: AtomicNativePtr,
    expected: NativePtr,
    update: NativePtr
): String {
    atomic.store(expected)
    val loaded = atomic.load()
    val exchanged = atomic.exchange(update)
    val previous = atomic.getAndSet(loaded)
    val compared = atomic.compareAndSet(expected, update)
    val witness = atomic.compareAndExchange(previous, loaded)
    val current = atomic.value
    atomic.value = current
    return "$loaded:$exchanged:$previous:$compared:$witness:$current:${atomic.toString()}"
}
