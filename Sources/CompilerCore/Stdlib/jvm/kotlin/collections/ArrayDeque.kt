package kotlin.collections

import kotlin.jvm.internal.__jvmListModified

public class ArrayDeque<E>(initialCapacity: Int) : AbstractMutableList<E>(), java.util.RandomAccess {
    private var elements: Array<Any?>
    private var head = 0
    private var count = 0

    init {
        require(initialCapacity >= 0) { "Illegal Capacity: $initialCapacity" }
        elements = arrayOfNulls<Any>(initialCapacity)
    }

    public constructor() : this(0)
    public constructor(elements: Collection<E>) : this(elements.size) {
        for (element in elements) addLast(element)
    }

    override val size: Int get() = count
    override fun isEmpty(): Boolean = count == 0

    private fun physical(index: Int): Int {
        val untilWrap = elements.size - head
        return if (index < untilWrap) head + index else index - untilWrap
    }

    private fun ensureRoom() {
        if (count < elements.size) return
        if (count == Int.MAX_VALUE) throw OutOfMemoryError()
        val expanded = count.toLong() + count / 2 + 1L
        val capacity = if (count < 10) 10 else if (expanded > Int.MAX_VALUE) Int.MAX_VALUE else expanded.toInt()
        val replacement = arrayOfNulls<Any>(capacity)
        for (index in 0 until count) replacement[index] = elements[physical(index)]
        elements = replacement
        head = 0
    }

    private fun checkIndex(index: Int, end: Int) {
        if (index < 0 || index >= end) throw IndexOutOfBoundsException("index: $index, size: $count")
    }

    override operator fun get(index: Int): E {
        checkIndex(index, count)
        return elements[physical(index)] as E
    }

    override operator fun set(index: Int, element: E): E {
        val previous = get(index)
        elements[physical(index)] = element
        return previous
    }

    public fun first(): E {
        if (isEmpty()) throw NoSuchElementException("ArrayDeque is empty.")
        return get(0)
    }

    public fun last(): E {
        if (isEmpty()) throw NoSuchElementException("ArrayDeque is empty.")
        return get(count - 1)
    }

    public fun firstOrNull(): E? = if (isEmpty()) null else first()
    public fun lastOrNull(): E? = if (isEmpty()) null else last()

    public fun addFirst(element: E) {
        ensureRoom()
        head = if (head == 0) elements.size - 1 else head - 1
        elements[head] = element
        count++
        __jvmListModified(this)
    }

    public fun addLast(element: E) {
        ensureRoom()
        elements[physical(count)] = element
        count++
        __jvmListModified(this)
    }

    public fun removeFirst(): E {
        val value = first()
        elements[head] = null
        head = physical(1)
        count--
        __jvmListModified(this)
        return value
    }

    public fun removeLast(): E {
        val value = last()
        count--
        elements[physical(count)] = null
        __jvmListModified(this)
        return value
    }

    public fun removeFirstOrNull(): E? = if (isEmpty()) null else removeFirst()
    public fun removeLastOrNull(): E? = if (isEmpty()) null else removeLast()

    public fun add(element: E): Boolean {
        addLast(element)
        return true
    }

    override fun add(index: Int, element: E) {
        if (index == 0) { addFirst(element); return }
        if (index == count) { addLast(element); return }
        checkIndex(index, count)
        ensureRoom()
        var position = count
        while (position > index) {
            elements[physical(position)] = elements[physical(position - 1)]
            position--
        }
        elements[physical(index)] = element
        count++
        __jvmListModified(this)
    }

    public fun addAll(elements: Collection<E>): Boolean = addAll(count, elements)

    public fun addAll(index: Int, elements: Collection<E>): Boolean {
        if (index < 0 || index > count) throw IndexOutOfBoundsException("index: $index, size: $count")
        if (elements.isEmpty()) return false
        val copy = ArrayDeque<E>(elements)
        for (offset in 0 until copy.size) add(index + offset, copy[offset])
        return true
    }

    override fun removeAt(index: Int): E {
        if (index == 0 && count != 0) return removeFirst()
        val previous = get(index)
        var position = index
        while (position < count - 1) {
            elements[physical(position)] = elements[physical(position + 1)]
            position++
        }
        count--
        elements[physical(count)] = null
        __jvmListModified(this)
        return previous
    }

    public fun clear() {
        while (count > 0) removeLast()
        head = 0
    }
}
