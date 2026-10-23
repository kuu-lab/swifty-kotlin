package kotlin.jvm.internal
@kotlin.jvm.JvmInline
value class ULongArrayValue(val storage: LongArray): Collection<ULongValue>, Iterable<ULongValue>, kotlin.jvm.internal.markers.KMappedMarker {
    constructor(size: Int): this(LongArray(size))
    fun getSize(): Int = storage.size
    override val size: Int get() = storage.size
    override fun isEmpty(): Boolean = storage.size == 0
    override fun contains(element: ULongValue): Boolean {
        var index = 0
        while (index < storage.size) { if (storage[index] == element.data) return true; index++ }
        return false
    }
    @kotlin.jvm.JvmName("get-s-VKNKU")
    operator fun get(index: Int): ULongValue = ULongValue(storage[index])
    @kotlin.jvm.JvmName("set-k8EXiF4")
    operator fun set(index: Int, value: ULongValue) { storage[index] = value.data }
    override fun iterator(): Iterator<ULongValue> = object: Iterator<ULongValue> {
        private var index = 0
        override fun hasNext(): Boolean = index < storage.size
        override fun next(): ULongValue {
            if (!hasNext()) throw NoSuchElementException()
            return ULongValue(storage[index++])
        }
    }
    override fun containsAll(elements: Collection<ULongValue>): Boolean {
        for (element in elements as Collection<*>) {
            if (!(element is ULongValue) || !contains(element)) return false
        }
        return true
    }
    fun toArray(): Array<Any?> {
        val result = arrayOfNulls<Any?>(storage.size)
        var index = 0
        while (index < storage.size) { result[index] = ULongValue(storage[index]); index++ }
        return result
    }
    fun <T> toArray(array: Array<T>): Array<T> {
        val result = if (array.size < storage.size) __jvmCopyArray(array, storage.size) else array
        var index = 0
        while (index < storage.size) { result[index] = ULongValue(storage[index]) as T; index++ }
        if (result.size > storage.size) result[storage.size] = null as T
        return result
    }
    fun add(element: Any?): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun remove(element: Any?): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun addAll(elements: Collection<*>): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun removeAll(elements: Collection<*>): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun retainAll(elements: Collection<*>): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun clear() { throw UnsupportedOperationException("Operation is not supported for read-only collection") }

}
