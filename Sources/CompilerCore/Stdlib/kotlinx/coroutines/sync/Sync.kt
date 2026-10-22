package kotlinx.coroutines.sync

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_mutex_create")
internal external fun __kkMutexCreate(): Mutex

@KsSymbolName("__kk_mutex_isLocked")
internal external fun __kkMutexIsLocked(mutex: Mutex): Boolean

@KsSymbolName("__kk_mutex_holdsLock")
internal external fun __kkMutexHoldsLock(mutex: Mutex, owner: Any): Boolean

@KsSymbolName("__kk_mutex_tryLock")
internal external fun __kkMutexTryLock(mutex: Mutex): Boolean

@KsSymbolName("__kk_mutex_tryLock_owner")
internal external fun __kkMutexTryLockOwner(mutex: Mutex, owner: Any?): Boolean

public fun Mutex(locked: Boolean = false): Mutex {
    val mutex = __kkMutexCreate()
    // The fresh handle is not observable until its anonymous initial lock is set.
    if (locked) __kkMutexTryLock(mutex)
    return mutex
}

public val Mutex.isLocked: Boolean
    get() = __kkMutexIsLocked(this)

public fun Mutex.holdsLock(owner: Any): Boolean = __kkMutexHoldsLock(this, owner)

public fun Mutex.tryLock(): Boolean = __kkMutexTryLock(this)

public fun Mutex.tryLock(owner: Any?): Boolean = __kkMutexTryLockOwner(this, owner)

public suspend fun <T> Mutex.withLock(action: suspend () -> T): T {
    lock()
    try {
        return action()
    } finally {
        unlock()
    }
}

@KsSymbolName("__kk_semaphore_create")
internal external fun __kkSemaphoreCreate(permits: Int): Semaphore

@KsSymbolName("__kk_semaphore_availablePermits")
internal external fun __kkSemaphoreAvailablePermits(semaphore: Semaphore): Int

@KsSymbolName("__kk_semaphore_tryAcquire")
internal external fun __kkSemaphoreTryAcquire(semaphore: Semaphore): Boolean

public fun Semaphore(permits: Int): Semaphore = __kkSemaphoreCreate(permits)

public val Semaphore.availablePermits: Int
    get() = __kkSemaphoreAvailablePermits(this)

public fun Semaphore.tryAcquire(): Boolean = __kkSemaphoreTryAcquire(this)

public suspend fun <T> Semaphore.withPermit(action: suspend () -> T): T {
    acquire()
    try {
        return action()
    } finally {
        release()
    }
}
