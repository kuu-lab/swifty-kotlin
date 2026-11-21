package java.util.concurrent.locks

public interface ReadWriteLock {
    public fun readLock(): Lock

    public fun writeLock(): Lock
}
