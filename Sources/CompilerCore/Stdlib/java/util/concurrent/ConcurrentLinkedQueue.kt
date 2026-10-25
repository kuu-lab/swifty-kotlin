package java.util.concurrent

import java.util.Queue
import kotlinx.atomicfu.locks.SynchronizedObject

// KUU-3059: java.util.concurrent.ConcurrentLinkedQueue over a lock-guarded
// kotlin.collections.ArrayDeque. Iterators are snapshots taken under the
// guard; they are weakly consistent like the JVM ones but cannot observe
// in-flight mutation.

public class ConcurrentLinkedQueue<E> private constructor(
    private val storage: ArrayDeque<E>
) : Queue<E> {
    private val guard = SynchronizedObject()

    public constructor() : this(ArrayDeque<E>())

    public constructor(elements: Collection<E>) : this(ArrayDeque<E>(elements))

    override fun add(element: E): Boolean {
        if (element == null) throw NullPointerException()
        guard.lock()
        try {
            storage.addLast(element)
        } finally {
            guard.unlock()
        }
        return true
    }

    override fun offer(element: E): Boolean = add(element)

    override fun poll(): E? {
        guard.lock()
        try {
            return storage.removeFirstOrNull()
        } finally {
            guard.unlock()
        }
    }

    override fun peek(): E? {
        guard.lock()
        try {
            return storage.firstOrNull()
        } finally {
            guard.unlock()
        }
    }

    override fun element(): E {
        guard.lock()
        try {
            if (storage.isEmpty()) throw NoSuchElementException()
            return storage.first()
        } finally {
            guard.unlock()
        }
    }

    public fun remove(): E {
        guard.lock()
        try {
            if (storage.isEmpty()) throw NoSuchElementException()
            return storage.removeFirst()
        } finally {
            guard.unlock()
        }
    }

    override val size: Int
        get() {
            guard.lock()
            try {
                return storage.size
            } finally {
                guard.unlock()
            }
        }

    override fun isEmpty(): Boolean {
        guard.lock()
        try {
            return storage.isEmpty()
        } finally {
            guard.unlock()
        }
    }

    override fun contains(element: E): Boolean {
        guard.lock()
        try {
            return storage.contains(element)
        } finally {
            guard.unlock()
        }
    }

    override fun containsAll(elements: Collection<E>): Boolean {
        guard.lock()
        try {
            return storage.containsAll(elements)
        } finally {
            guard.unlock()
        }
    }

    override fun addAll(elements: Collection<E>): Boolean {
        var changed = false
        for (element in elements) {
            if (add(element)) changed = true
        }
        return changed
    }

    override fun remove(element: E): Boolean {
        guard.lock()
        try {
            return storage.remove(element)
        } finally {
            guard.unlock()
        }
    }

    override fun removeAll(elements: Collection<E>): Boolean {
        guard.lock()
        try {
            return storage.removeAll(elements)
        } finally {
            guard.unlock()
        }
    }

    override fun retainAll(elements: Collection<E>): Boolean {
        guard.lock()
        try {
            return storage.retainAll(elements)
        } finally {
            guard.unlock()
        }
    }

    override fun clear() {
        guard.lock()
        try {
            storage.clear()
        } finally {
            guard.unlock()
        }
    }

    override fun iterator(): MutableIterator<E> {
        guard.lock()
        try {
            return storage.toList().toMutableList().iterator()
        } finally {
            guard.unlock()
        }
    }

    public fun toArray(): Array<Any?> {
        guard.lock()
        try {
            return storage.toArray()
        } finally {
            guard.unlock()
        }
    }

    override fun toString(): String {
        guard.lock()
        try {
            return storage.toString()
        } finally {
            guard.unlock()
        }
    }
}
