package kotlinx.coroutines.sync

import kotlin.internal.KsSymbolName

// KSP-677: Mutex/Semaphore public wrapper layer migrated to Kotlin. The
// composition helpers (withLock/withPermit) are expressed here in terms of the
// c-soft kernel primitives (lock/unlock, acquire/release), so their dedicated
// runtime entry points (kk_mutex_withLock, kk_semaphore_withPermit) are removed.
// The factory/accessor helpers delegate to demoted __kk_* runtime bridges.

// -- Mutex --

@KsSymbolName("__kk_mutex_create")
internal external fun __kkMutexCreate(): Mutex

@KsSymbolName("__kk_mutex_isLocked")
internal external fun __kkMutexIsLocked(mutex: Mutex): Boolean

@KsSymbolName("__kk_mutex_tryLock")
internal external fun __kkMutexTryLock(mutex: Mutex): Boolean

public fun Mutex(): Mutex = __kkMutexCreate()

public val Mutex.isLocked: Boolean
    get() = __kkMutexIsLocked(this)

public fun Mutex.tryLock(): Boolean = __kkMutexTryLock(this)

public suspend fun <T> Mutex.withLock(action: suspend () -> T): T {
    lock()
    try {
        return action()
    } finally {
        unlock()
    }
}

// -- Semaphore --

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
