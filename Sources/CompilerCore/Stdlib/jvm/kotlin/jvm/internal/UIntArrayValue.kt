package kotlin.jvm.internal
@kotlin.jvm.JvmInline
value class UIntArrayValue(val storage: IntArray): Collection<UIntValue>, Iterable<UIntValue>, kotlin.jvm.internal.markers.KMappedMarker {
    constructor(size: Int): this(IntArray(size))
    fun getSize(): Int = storage.size
    override val size: Int get() = storage.size
    override fun isEmpty(): Boolean = storage.size == 0
    override fun contains(element: UIntValue): Boolean {
        var index = 0
        while (index < storage.size) { if (storage[index] == element.data) return true; index++ }
        return false
    }
    @kotlin.jvm.JvmName("get-pVg5ArA")
    operator fun get(index: Int): UIntValue = UIntValue(storage[index])
    @kotlin.jvm.JvmName("set-VXSXFK8")
    operator fun set(index: Int, value: UIntValue) { storage[index] = value.data }
    override fun iterator(): Iterator<UIntValue> = object: Iterator<UIntValue> {
        private var index = 0
        override fun hasNext(): Boolean = index < storage.size
        override fun next(): UIntValue {
            if (!hasNext()) throw NoSuchElementException()
            return UIntValue(storage[index++])
        }
    }
    override fun containsAll(elements: Collection<*>): Boolean {
        for (element in elements) {
            if (!(element is UIntValue) || !contains(element)) return false
        }
        return true
    }
    fun toArray(): Array<Any?> {
        val result = arrayOfNulls<Any?>(storage.size)
        var index = 0
        while (index < storage.size) { result[index] = UIntValue(storage[index]); index++ }
        return result
    }
    fun <T> toArray(array: Array<T>): Array<T> {
        val result = if (array.size < storage.size) __jvmCopyArray(array, storage.size) else array
        var index = 0
        while (index < storage.size) { result[index] = UIntValue(storage[index]) as T; index++ }
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
