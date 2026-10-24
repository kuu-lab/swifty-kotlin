package java.util.concurrent.locks

// KUU-3059: java.util.concurrent.locks.ReadWriteLock — paired read/write
// views over one lock state, implemented by ReentrantReadWriteLock.
public interface ReadWriteLock {
    public fun readLock(): Lock

    public fun writeLock(): Lock
}
