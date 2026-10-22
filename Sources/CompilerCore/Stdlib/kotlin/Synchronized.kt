package kotlin

// The lock helpers share the runtime monitor table with lazy. Keep the block
// invocation inside this inline body so non-local returns still unlock in finally.
public inline fun <R> synchronized(lock: Any, block: () -> R): R {
    __lazySyncLock(lock)
    try {
        return block()
    } finally {
        __lazySyncUnlock(lock)
    }
}
