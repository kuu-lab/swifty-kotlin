package java.util

public open class PriorityQueue<E>(
    initialCapacity: Int,
    private val ordering: Comparator<in E>?
) : AbstractMutableCollection<E>() {
    private val heap: MutableList<Entry<E>> = ArrayList<Entry<E>>(initialCapacity)
    private var modCount: Int = 0

    init {
        if (initialCapacity < 1) throw IllegalArgumentException()
    }

    public constructor() : this(11, null)
    public constructor(initialCapacity: Int) : this(initialCapacity, null)
    public constructor(comparator: Comparator<in E>?) : this(11, comparator)

    override val size: Int get() = heap.size
    override fun isEmpty(): Boolean = heap.isEmpty()
    public fun comparator(): Comparator<in E>? = ordering

    @IgnorableReturnValue
    override fun add(element: E): Boolean = offer(element)

    @IgnorableReturnValue
    public fun offer(element: E): Boolean {
        if (element == null) throw NullPointerException()
        if (ordering == null && element !is Comparable<*>) throw ClassCastException()
        var insertion = heap.size
        while (insertion > 0) {
            val parent = (insertion - 1) / 2
            if (compare(element, heap[parent].value) >= 0) break
            insertion = parent
        }
        val entry = Entry(element)
        heap.add(entry)
        var index = heap.lastIndex
        while (index > insertion) {
            val parent = (index - 1) / 2
            heap[index] = heap[parent]
            index = parent
        }
        heap[insertion] = entry
        modCount += 1
        return true
    }

    public fun peek(): E? = if (isEmpty()) null else heap[0].value
    public fun poll(): E? = if (isEmpty()) null else removeAt(0)

    public fun element(): E {
        if (isEmpty()) throw NoSuchElementException()
        return heap[0].value
    }

    public fun remove(): E {
        if (isEmpty()) throw NoSuchElementException()
        return removeAt(0)
    }

    @IgnorableReturnValue
    override fun remove(element: E): Boolean {
        var index = 0
        while (index < heap.size) {
            if (heap[index].value == element) {
                removeAt(index)
                return true
            }
            index += 1
        }
        return false
    }

    override fun clear() {
        heap.clear()
        modCount += 1
    }

    override fun iterator(): MutableIterator<E> = HeapIterator(this)

    @Suppress("UNCHECKED_CAST")
    private fun compare(left: E, right: E): Int {
        val comparator = ordering
        return if (comparator != null) comparator.compare(left, right)
        else (left as Comparable<E>).compareTo(right)
    }

    private fun siftUp(start: Int) {
        var index = start
        val value = heap[index]
        while (index > 0) {
            val parent = (index - 1) / 2
            if (compare(value.value, heap[parent].value) >= 0) break
            heap[index] = heap[parent]
            index = parent
        }
        heap[index] = value
    }

    private fun siftDown(start: Int) {
        var index = start
        val value = heap[index]
        while (index < heap.size / 2) {
            var child = index * 2 + 1
            val right = child + 1
            if (right < heap.size && compare(heap[right].value, heap[child].value) < 0) child = right
            if (compare(value.value, heap[child].value) <= 0) break
            heap[index] = heap[child]
            index = child
        }
        heap[index] = value
    }

    private fun removeAt(index: Int): E {
        val removed = heap[index]
        val last = heap.removeAt(heap.lastIndex)
        if (index < heap.size) {
            heap[index] = last
            if (index > 0 && compare(last.value, heap[(index - 1) / 2].value) < 0) siftUp(index)
            else siftDown(index)
        }
        modCount += 1
        return removed.value
    }

    private fun removeIdentity(element: Entry<E>) {
        var index = 0
        while (index < heap.size) {
            if (heap[index] === element) {
                removeAt(index)
                return
            }
            index += 1
        }
    }

    // Keep entry identity across collection ABI boxing and heap reordering.
    private class Entry<T>(val value: T)

    // Snapshot the heap order so reheapification cannot skip or repeat elements.
    private class HeapIterator<T>(private val owner: PriorityQueue<T>) : MutableIterator<T> {
        private val snapshot: List<Entry<T>> = owner.heap.toList()
        private var cursor: Int = 0
        private var last: Int = -1
        private var expectedModCount: Int = owner.modCount

        override fun hasNext(): Boolean = cursor < snapshot.size

        override fun next(): T {
            checkForModification()
            if (!hasNext()) throw NoSuchElementException()
            last = cursor
            cursor += 1
            return snapshot[last].value
        }

        override fun remove() {
            checkForModification()
            if (last < 0) throw IllegalStateException()
            owner.removeIdentity(snapshot[last])
            expectedModCount = owner.modCount
            last = -1
        }

        private fun checkForModification() {
            if (owner.modCount != expectedModCount) throw ConcurrentModificationException()
        }
    }
}
