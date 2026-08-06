package kotlin

import kotlin.internal.KsSymbolName

// KSP-618: the public synchronized(lock) { } layer is Kotlin source. Locking
// itself needs per-object reentrant locks owned by the runtime, so it stays
// behind the demoted __kk_synchronized bridge (Sources/Runtime/RuntimePreconditions.swift),
// which acquires the lock, runs the block and propagates a thrown exception.

@KsSymbolName("__kk_synchronized")
internal external fun <R> __kkSynchronized(lock: Any, block: () -> R): R

public fun <R> synchronized(lock: Any, block: () -> R): R = __kkSynchronized(lock, block)
