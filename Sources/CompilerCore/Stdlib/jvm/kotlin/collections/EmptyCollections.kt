package kotlin.collections

import kotlin.jvm.internal.markers.KMappedMarker

private fun readOnlyCollection(): Unit = throw UnsupportedOperationException("Operation is not supported for read-only collection")

// Preserve Kotlin's mapped marker while inheriting the complete JDK collection
// ABI, including both toArray overloads and list iteration helpers.
internal object EmptyList: java.util.AbstractList<Any?>(), KMappedMarker, java.util.RandomAccess, java.io.Serializable {
    override val size: Int get() = 0
    fun size(): Int = 0
    override fun get(index: Int): Any? = throw IndexOutOfBoundsException("Empty list doesn't contain element at index $index.")
    fun iterator(): Iterator<Any?> = EmptyIterator
    override fun listIterator(): java.util.ListIterator<Any?> = EmptyIterator
    override fun listIterator(index: Int): java.util.ListIterator<Any?> {
        if (index != 0) throw IndexOutOfBoundsException("Index: $index")
        return EmptyIterator
    }
    fun subList(fromIndex: Int, toIndex: Int): List<Any?> {
        if (fromIndex != 0 || toIndex != 0) throw IndexOutOfBoundsException("fromIndex: $fromIndex, toIndex: $toIndex")
        return this as List<Any?>
    }
    fun add(element: Any?): Boolean { readOnlyCollection(); return false }
    fun add(index: Int, element: Any?) { readOnlyCollection() }
    fun set(index: Int, element: Any?): Any? { readOnlyCollection(); return null }
    fun remove(element: Any?): Boolean { readOnlyCollection(); return false }
    @kotlin.jvm.JvmName("remove")
    fun removeAt(index: Int): Any? { readOnlyCollection(); return null }
    fun addAll(elements: Collection<*>): Boolean { readOnlyCollection(); return false }
    fun addAll(index: Int, elements: Collection<*>): Boolean { readOnlyCollection(); return false }
    fun removeAll(elements: Collection<*>): Boolean { readOnlyCollection(); return false }
    fun retainAll(elements: Collection<*>): Boolean { readOnlyCollection(); return false }
    fun clear() { readOnlyCollection() }
}

internal object EmptySet: java.util.AbstractSet<Any?>(), KMappedMarker, java.io.Serializable {
    override val size: Int get() = 0
    fun size(): Int = 0
    fun iterator(): Iterator<Any?> = EmptyIterator
    fun add(element: Any?): Boolean { readOnlyCollection(); return false }
    fun remove(element: Any?): Boolean { readOnlyCollection(); return false }
    fun addAll(elements: Collection<*>): Boolean { readOnlyCollection(); return false }
    fun removeAll(elements: Collection<*>): Boolean { readOnlyCollection(); return false }
    fun retainAll(elements: Collection<*>): Boolean { readOnlyCollection(); return false }
    fun clear() { readOnlyCollection() }
}

internal object EmptyMap: java.util.AbstractMap<Any?, Any?>(), KMappedMarker, java.io.Serializable {
    override val size: Int get() = 0
    // Map's JVM ABI uses size/keySet/values rather than Kotlin property getters.
    fun size(): Int = 0
    override val keys: Set<Any?> get() = EmptySet as Set<Any?>
    override val values: Collection<Any?> get() = EmptyList as Collection<Any?>
    override fun entrySet(): Set<Any?> = EmptySet as Set<Any?>
    override fun keySet(): Set<Any?> = EmptySet as Set<Any?>
    override fun values(): Collection<Any?> = EmptyList as Collection<Any?>
    fun put(key: Any?, value: Any?): Any? { readOnlyCollection(); return null }
    fun remove(key: Any?): Any? { readOnlyCollection(); return null }
    fun putAll(values: Map<*, *>) { readOnlyCollection() }
    fun clear() { readOnlyCollection() }
}

private object EmptyIterator: java.util.ListIterator<Any?>, KMappedMarker {
    override fun hasNext(): Boolean = false
    override fun hasPrevious(): Boolean = false
    override fun next(): Any? = throw NoSuchElementException()
    override fun previous(): Any? = throw NoSuchElementException()
    override fun nextIndex(): Int = 0
    override fun previousIndex(): Int = -1
    override fun add(element: Any?) { readOnlyCollection() }
    override fun set(element: Any?) { readOnlyCollection() }
    override fun remove() { readOnlyCollection() }
}
