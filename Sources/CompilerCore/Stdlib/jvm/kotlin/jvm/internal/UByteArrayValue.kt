package kotlin.jvm.internal
@kotlin.jvm.JvmInline
value class UByteArrayValue(val storage: ByteArray): Collection<UByteValue>, Iterable<UByteValue>, kotlin.jvm.internal.markers.KMappedMarker {
    constructor(size: Int): this(ByteArray(size))
    fun getSize(): Int = storage.size
    override val size: Int get() = storage.size
    override fun isEmpty(): Boolean = storage.size == 0
    override fun contains(element: UByteValue): Boolean {
        var index = 0
        while (index < storage.size) { if (storage[index] == element.data) return true; index++ }
        return false
    }
    @kotlin.jvm.JvmName("get-w2LRezQ")
    operator fun get(index: Int): UByteValue = UByteValue(storage[index])
    @kotlin.jvm.JvmName("set-VurrAj0")
    operator fun set(index: Int, value: UByteValue) { storage[index] = value.data }
    override fun iterator(): Iterator<UByteValue> = object: Iterator<UByteValue> {
        private var index = 0
        override fun hasNext(): Boolean = index < storage.size
        override fun next(): UByteValue {
            if (!hasNext()) throw NoSuchElementException()
            return UByteValue(storage[index++])
        }
    }
    override fun containsAll(elements: Collection<UByteValue>): Boolean {
        for (element in elements) {
            if (!(element is UByteValue) || !contains(element)) return false
        }
        return true
    }
    fun toArray(): Array<Any?> {
        val result = arrayOfNulls<Any?>(storage.size)
        var index = 0
        while (index < storage.size) { result[index] = UByteValue(storage[index]); index++ }
        return result
    }
    fun <T> toArray(array: Array<T>): Array<T> {
        val result = if (array.size < storage.size) __jvmCopyArray(array, storage.size) else array
        var index = 0
        while (index < storage.size) { result[index] = UByteValue(storage[index]) as T; index++ }
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
