/* Explicit recording retry/update operations. Real CAS remains in the delegate. */
package kswiftk.atomicfu

public inline fun RecordingAtomicInt.loop(action: (Int) -> Unit): Nothing {
    while (true) action(value)
}
public inline fun RecordingAtomicInt.update(function: (Int) -> Int) {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return
    }
}
public inline fun RecordingAtomicInt.getAndUpdate(function: (Int) -> Int): Int {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return current
    }
}
public inline fun RecordingAtomicInt.updateAndGet(function: (Int) -> Int): Int {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return updated
    }
}

public inline fun RecordingAtomicLong.loop(action: (Long) -> Unit): Nothing {
    while (true) action(value)
}
public inline fun RecordingAtomicLong.update(function: (Long) -> Long) {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return
    }
}
public inline fun RecordingAtomicLong.getAndUpdate(function: (Long) -> Long): Long {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return current
    }
}
public inline fun RecordingAtomicLong.updateAndGet(function: (Long) -> Long): Long {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return updated
    }
}

public inline fun RecordingAtomicBoolean.loop(action: (Boolean) -> Unit): Nothing {
    while (true) action(value)
}
public inline fun RecordingAtomicBoolean.update(function: (Boolean) -> Boolean) {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return
    }
}
public inline fun RecordingAtomicBoolean.getAndUpdate(function: (Boolean) -> Boolean): Boolean {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return current
    }
}
public inline fun RecordingAtomicBoolean.updateAndGet(function: (Boolean) -> Boolean): Boolean {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return updated
    }
}

public inline fun <T> RecordingAtomicRef<T>.loop(action: (T) -> Unit): Nothing {
    while (true) action(value)
}
public inline fun <T> RecordingAtomicRef<T>.update(function: (T) -> T) {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return
    }
}
public inline fun <T> RecordingAtomicRef<T>.getAndUpdate(function: (T) -> T): T {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return current
    }
}
public inline fun <T> RecordingAtomicRef<T>.updateAndGet(function: (T) -> T): T {
    while (true) {
        val current = value
        val updated = function(current)
        if (compareAndSet(current, updated)) return updated
    }
}
