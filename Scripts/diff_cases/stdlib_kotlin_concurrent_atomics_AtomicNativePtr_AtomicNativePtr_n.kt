// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent.atomics is Native-only
// in Kotlin 2.3.10 and is unavailable in the JVM kotlinc reference environment.

@file:OptIn(
    kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
    kotlinx.cinterop.ExperimentalForeignApi::class
)

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

fun main() {}
