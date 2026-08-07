package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-625
// ArrayDeque public surface migrated to bundled Kotlin source. first/last/
// isEmpty/toString are pure Kotlin now; only the ring-buffer mutation core
// stays in the runtime behind the demoted __kk_arraydeque_* bridges
// (Sources/Runtime/RuntimeArrayDequeAndUtility.swift).

@KsSymbolName("__kk_arraydeque_new")
private external fun __kkArrayDequeNew(): Any

@KsSymbolName("__kk_arraydeque_size")
private external fun __kkArrayDequeSize(handle: Any): Int

@KsSymbolName("__kk_arraydeque_get")
private external fun __kkArrayDequeGet(handle: Any, index: Int): Any?

@KsSymbolName("__kk_arraydeque_addFirst")
private external fun __kkArrayDequeAddFirst(handle: Any, element: Any?): Int

@KsSymbolName("__kk_arraydeque_addLast")
private external fun __kkArrayDequeAddLast(handle: Any, element: Any?): Int

@KsSymbolName("__kk_arraydeque_removeFirst")
private external fun __kkArrayDequeRemoveFirst(handle: Any): Any?

@KsSymbolName("__kk_arraydeque_removeLast")
private external fun __kkArrayDequeRemoveLast(handle: Any): Any?

/**
 * Resizable-array implementation of the deque data structure.
 *
 * The element storage is the runtime ring buffer reached through [handle];
 * every operation above the raw buffer mutation is implemented here.
 */
public class ArrayDeque<E> {
    private val handle: Any = __kkArrayDequeNew()

    public val size: Int
        get() = __kkArrayDequeSize(handle)

    public fun isEmpty(): Boolean = size == 0

    public fun isNotEmpty(): Boolean = size != 0

    public fun addFirst(element: E) {
        __kkArrayDequeAddFirst(handle, element)
    }

    public fun addLast(element: E) {
        __kkArrayDequeAddLast(handle, element)
    }

    @Suppress("UNCHECKED_CAST")
    public operator fun get(index: Int): E {
        checkElementIndex(index)
        return __kkArrayDequeGet(handle, index) as E
    }

    public fun first(): E {
        checkNotEmpty()
        return get(0)
    }

    public fun last(): E {
        checkNotEmpty()
        return get(size - 1)
    }

    public fun firstOrNull(): E? = if (isEmpty()) null else get(0)

    public fun lastOrNull(): E? = if (isEmpty()) null else get(size - 1)

    @Suppress("UNCHECKED_CAST")
    public fun removeFirst(): E {
        checkNotEmpty()
        return __kkArrayDequeRemoveFirst(handle) as E
    }

    @Suppress("UNCHECKED_CAST")
    public fun removeLast(): E {
        checkNotEmpty()
        return __kkArrayDequeRemoveLast(handle) as E
    }

    public fun removeFirstOrNull(): E? = if (isEmpty()) null else removeFirst()

    public fun removeLastOrNull(): E? = if (isEmpty()) null else removeLast()

    override fun toString(): String {
        var result = "["
        var index = 0
        val count = size
        while (index < count) {
            if (index > 0) result += ", "
            result += get(index).toString()
            index += 1
        }
        return result + "]"
    }

    private fun checkNotEmpty() {
        if (size == 0) throw NoSuchElementException("ArrayDeque is empty.")
    }

    private fun checkElementIndex(index: Int) {
        val count = size
        if (index < 0 || index >= count) {
            throw IndexOutOfBoundsException("index: $index, size: $count")
        }
    }
}
