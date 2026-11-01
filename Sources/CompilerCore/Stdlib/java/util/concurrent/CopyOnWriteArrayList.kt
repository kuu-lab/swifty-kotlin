package java.util.concurrent

import java.lang.Cloneable
import kotlinx.atomicfu.locks.SynchronizedObject

// KUU-4032: java.util.concurrent.CopyOnWriteArrayList — every mutator rebuilds
// the backing store as a fresh immutable List under the guard, so reads never
// lock and iterators capture a true snapshot: they never observe in-flight
// mutation and never throw ConcurrentModificationException. Iterator and
// list-iterator mutators throw UnsupportedOperationException exactly like the
// JVM snapshot iterators. `subList` returns a detached mutable snapshot rather
// than the JVM live view — sufficient for snapshot-style reads.

public class CopyOnWriteArrayList<E> private constructor(
    private var storage: List<E>
) : MutableList<E>, Cloneable {
    private val guard = SynchronizedObject()

    public constructor() : this(emptyList())

    public constructor(elements: Collection<E>) : this(elements.toList())

    public constructor(elements: Array<out E>) : this(elements.toList())

    override val size: Int
        get() = storage.size

    override fun isEmpty(): Boolean = storage.isEmpty()

    override operator fun get(index: Int): E = storage[index]

    override fun contains(element: E): Boolean = storage.contains(element)

    override fun containsAll(elements: Collection<E>): Boolean = storage.containsAll(elements)

    override fun indexOf(element: E): Int = storage.indexOf(element)

    override fun lastIndexOf(element: E): Int = storage.lastIndexOf(element)

    /** JVM `indexOf(Object, int)`: first index at or after [index], or -1. */
    public fun indexOf(element: E, index: Int): Int {
        val snapshot = storage
        var cursor = if (index < 0) 0 else index
        while (cursor < snapshot.size) {
            if (snapshot[cursor] == element) return cursor
            cursor += 1
        }
        return -1
    }

    /** JVM `lastIndexOf(Object, int)`: last index at or before [index], or -1. */
    public fun lastIndexOf(element: E, index: Int): Int {
        val snapshot = storage
        var cursor = if (index >= snapshot.size) snapshot.size - 1 else index
        while (cursor >= 0) {
            if (snapshot[cursor] == element) return cursor
            cursor -= 1
        }
        return -1
    }

    override operator fun set(index: Int, element: E): E = guardedCopy { copy ->
        copy.set(index, element)
    }

    override fun add(element: E): Boolean = guardedCopy { copy ->
        copy.add(element)
    }

    override fun add(index: Int, element: E): Unit = guardedCopy { copy ->
        copy.add(index, element)
    }

    override fun addAll(elements: Collection<E>): Boolean {
        if (elements.isEmpty()) return false
        return guardedCopy { copy -> copy.addAll(elements) }
    }

    override fun addAll(index: Int, elements: Collection<E>): Boolean {
        if (elements.isEmpty()) {
            // Still validates the position index like the JVM implementation.
            if (index < 0 || index > storage.size) {
                throw IndexOutOfBoundsException("index: $index, size: ${storage.size}")
            }
            return false
        }
        return guardedCopy { copy -> copy.addAll(index, elements) }
    }

    override fun removeAt(index: Int): E = guardedCopy { copy ->
        copy.removeAt(index)
    }

    override fun remove(element: E): Boolean {
        // Skip the copy when the element is absent — reads stay cheap.
        if (!storage.contains(element)) return false
        return guardedCopy { copy -> copy.remove(element) }
    }

    override fun removeAll(elements: Collection<E>): Boolean {
        if (elements.isEmpty() || storage.isEmpty()) return false
        return guardedCopy { copy -> copy.removeAll(elements) }
    }

    override fun retainAll(elements: Collection<E>): Boolean {
        if (storage.isEmpty()) return false
        return guardedCopy { copy -> copy.retainAll(elements) }
    }

    override fun clear() {
        if (storage.isEmpty()) return
        guard.lock()
        try {
            storage = emptyList()
        } finally {
            guard.unlock()
        }
    }

    /** JVM `addIfAbsent`: appends [element] only when absent; true when added. */
    public fun addIfAbsent(element: E): Boolean {
        if (storage.contains(element)) return false
        return guardedCopy { copy ->
            // Re-check inside the guard: a concurrent add may have won.
            if (copy.contains(element)) false else {
                copy.add(element)
                true
            }
        }
    }

    /** JVM `addAllAbsent`: appends every absent element; returns the count added. */
    public fun addAllAbsent(elements: Collection<E>): Int {
        if (elements.isEmpty()) return 0
        return guardedCopy { copy ->
            var added = 0
            for (element in elements) {
                if (!copy.contains(element)) {
                    copy.add(element)
                    added += 1
                }
            }
            added
        }
    }

    public fun clone(): CopyOnWriteArrayList<E> = CopyOnWriteArrayList(storage)

    override fun iterator(): MutableIterator<E> = CowIterator(storage)

    override fun listIterator(): MutableListIterator<E> = CowListIterator(storage, 0)

    override fun listIterator(index: Int): MutableListIterator<E> = CowListIterator(storage, index)

    override fun subList(fromIndex: Int, toIndex: Int): MutableList<E> =
        storage.subList(fromIndex, toIndex).toMutableList()

    public fun toArray(): Array<Any?> {
        val snapshot = storage
        val result = arrayOfNulls<Any>(snapshot.size)
        var index = 0
        for (element in snapshot) {
            result[index] = element
            index += 1
        }
        return result
    }

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is List<*>) return false
        if (other is CopyOnWriteArrayList<*>) {
            return storage == other.storage
        }
        return storage == other
    }

    override fun hashCode(): Int = storage.hashCode()

    override fun toString(): String = storage.toString()

    /**
     * Replaces [storage] with a mutable copy after [block] mutates it. The
     * copy-and-swap is what makes iterators stable snapshots.
     */
    private inline fun <R> guardedCopy(block: (MutableList<E>) -> R): R {
        guard.lock()
        try {
            val copy = storage.toMutableList()
            val result = block(copy)
            storage = copy
            return result
        } finally {
            guard.unlock()
        }
    }
}

/** Snapshot iterator whose mutators fail like the JVM COW ones. */
private class CowIterator<E>(private val snapshot: List<E>) : MutableIterator<E> {
    private var cursor = 0

    override fun hasNext(): Boolean = cursor < snapshot.size

    override fun next(): E {
        if (!hasNext()) throw NoSuchElementException()
        cursor += 1
        return snapshot[cursor - 1]
    }

    override fun remove() {
        throw UnsupportedOperationException()
    }
}

private class CowListIterator<E>(private val snapshot: List<E>, index: Int) : MutableListIterator<E> {
    private var cursor: Int

    init {
        if (index < 0 || index > snapshot.size) {
            throw IndexOutOfBoundsException("index: $index, size: ${snapshot.size}")
        }
        cursor = index
    }

    override fun hasNext(): Boolean = cursor < snapshot.size

    override fun next(): E {
        if (!hasNext()) throw NoSuchElementException()
        cursor += 1
        return snapshot[cursor - 1]
    }

    override fun hasPrevious(): Boolean = cursor > 0

    override fun previous(): E {
        if (!hasPrevious()) throw NoSuchElementException()
        cursor -= 1
        return snapshot[cursor]
    }

    override fun nextIndex(): Int = cursor

    override fun previousIndex(): Int = cursor - 1

    override fun add(element: E) {
        throw UnsupportedOperationException()
    }

    override fun remove() {
        throw UnsupportedOperationException()
    }

    override fun set(element: E) {
        throw UnsupportedOperationException()
    }
}
