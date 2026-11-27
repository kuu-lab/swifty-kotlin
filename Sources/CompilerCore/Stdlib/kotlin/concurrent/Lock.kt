package kotlin.concurrent

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_lock_withLock")
internal external fun <T> __kkLockWithLock(lock: Lock, action: () -> T): T

public fun <T> Lock.withLock(action: () -> T): T = __kkLockWithLock(this, action)
