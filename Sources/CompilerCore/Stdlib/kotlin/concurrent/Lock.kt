package kotlin.concurrent

import kotlin.internal.KsSymbolName

// KSP-677: Lock.withLock public wrapper migrated to Kotlin source. The action
// runs while the c-soft kernel holds the lock, so the actual locking stays in the
// runtime as the demoted __kk_lock_withLock bridge (Sources/Runtime/RuntimeSync.swift).

@KsSymbolName("__kk_lock_withLock")
internal external fun <T> __kkLockWithLock(lock: Lock, action: () -> T): T

public fun <T> Lock.withLock(action: () -> T): T = __kkLockWithLock(this, action)
