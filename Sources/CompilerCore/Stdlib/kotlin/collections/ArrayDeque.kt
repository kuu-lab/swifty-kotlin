package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-625: ArrayDeque migrated to bundled Kotlin source.
// `first` / `last` / `isEmpty` / `toString` and the emptiness / bounds checks
// are Kotlin logic; only the ring-buffer mutation primitives stay in the
// runtime (`__kk_arraydeque_*`), because the element storage is a
// runtime-managed, GC-traced buffer.

@KsSymbolName("__kk_arraydeque_size")
private external fun <E> __kkArrayDequeSize(deque: ArrayDeque<E>): Int

@KsSymbolName("__kk_arraydeque_get")
private external fun <E> __kkArrayDequeGet(deque: ArrayDeque<E>, index: Int): E

@KsSymbolName("__kk_arraydeque_removeFirst")
private external fun <E> __kkArrayDequeRemoveFirst(deque: ArrayDeque<E>): E

@KsSymbolName("__kk_arraydeque_removeLast")
private external fun <E> __kkArrayDequeRemoveLast(deque: ArrayDeque<E>): E

/**
 * Resizable-array implementation of the deque data structure.
 */
public class ArrayDeque<E> {
    @KsSymbolName("__kk_arraydeque_new")
    public constructor()

    public val size: Int
        get() = __kkArrayDequeSize(this)

    public fun isEmpty(): Boolean = __kkArrayDequeSize(this) == 0

    @KsSymbolName("__kk_arraydeque_addFirst")
    public external fun addFirst(element: E): Unit

    @KsSymbolName("__kk_arraydeque_addLast")
    public external fun addLast(element: E): Unit

    public operator fun get(index: Int): E {
        val currentSize = __kkArrayDequeSize(this)
        if (index < 0 || index >= currentSize) {
            throw IndexOutOfBoundsException("index: $index, size: $currentSize")
        }
        return __kkArrayDequeGet(this, index)
    }

    public fun first(): E {
        if (__kkArrayDequeSize(this) == 0) throw NoSuchElementException("ArrayDeque is empty.")
        return __kkArrayDequeGet(this, 0)
    }

    public fun last(): E {
        val currentSize = __kkArrayDequeSize(this)
        if (currentSize == 0) throw NoSuchElementException("ArrayDeque is empty.")
        return __kkArrayDequeGet(this, currentSize - 1)
    }

    public fun removeFirst(): E {
        if (__kkArrayDequeSize(this) == 0) throw NoSuchElementException("ArrayDeque is empty.")
        return __kkArrayDequeRemoveFirst(this)
    }

    public fun removeLast(): E {
        if (__kkArrayDequeSize(this) == 0) throw NoSuchElementException("ArrayDeque is empty.")
        return __kkArrayDequeRemoveLast(this)
    }

    override fun toString(): String {
        val builder = StringBuilder()
        builder.append("[")
        var index = 0
        val currentSize = __kkArrayDequeSize(this)
        while (index < currentSize) {
            if (index > 0) builder.append(", ")
            builder.append(__kkArrayDequeGet(this, index).toString())
            index += 1
        }
        builder.append("]")
        return builder.toString()
    }
}
