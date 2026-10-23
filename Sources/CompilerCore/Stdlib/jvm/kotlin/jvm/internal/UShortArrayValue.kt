package kotlin.jvm.internal
@kotlin.jvm.JvmInline
value class UShortArrayValue(val storage: ShortArray): Collection<UShortValue>, Iterable<UShortValue>, kotlin.jvm.internal.markers.KMappedMarker {
    constructor(size: Int): this(ShortArray(size))
    fun getSize(): Int = storage.size
    override val size: Int get() = storage.size
    override fun isEmpty(): Boolean = storage.size == 0
    override fun contains(element: UShortValue): Boolean {
        var index = 0
        while (index < storage.size) { if (storage[index] == element.data) return true; index++ }
        return false
    }
    @kotlin.jvm.JvmName("get-Mh2AYeg")
    operator fun get(index: Int): UShortValue = UShortValue(storage[index])
    @kotlin.jvm.JvmName("set-01HTLdE")
    operator fun set(index: Int, value: UShortValue) { storage[index] = value.data }
    override fun iterator(): Iterator<UShortValue> = object: Iterator<UShortValue> {
        private var index = 0
        override fun hasNext(): Boolean = index < storage.size
        override fun next(): UShortValue {
            if (!hasNext()) throw NoSuchElementException()
            return UShortValue(storage[index++])
        }
    }
    override fun containsAll(elements: Collection<UShortValue>): Boolean {
        for (element in elements) {
            if (!(element is UShortValue) || !contains(element)) return false
        }
        return true
    }
    fun toArray(): Array<Any?> {
        val result = arrayOfNulls<Any?>(storage.size)
        var index = 0
        while (index < storage.size) { result[index] = UShortValue(storage[index]); index++ }
        return result
    }
    fun <T> toArray(array: Array<T>): Array<T> {
        val result = if (array.size < storage.size) __jvmCopyArray(array, storage.size) else array
        var index = 0
        while (index < storage.size) { result[index] = UShortValue(storage[index]) as T; index++ }
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
