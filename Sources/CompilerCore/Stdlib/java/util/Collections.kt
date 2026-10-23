package java.util

public object Collections {
    public fun <T> unmodifiableList(list: List<T>?): MutableList<T> =
        collectionsUnmodifiableList(list!!)

    public fun <T> unmodifiableSet(set: Set<T>?): MutableSet<T> =
        CollectionsUnmodifiableSet(set!!)

    public fun <K, V> unmodifiableMap(map: Map<out K, V>?): MutableMap<K, V> =
        CollectionsUnmodifiableMap(map!!)

    @Suppress("UNCHECKED_CAST")
    public fun <E> newSetFromMap(map: MutableMap<E, out Boolean?>?): MutableSet<E> {
        val backing = map!!
        if (!backing.isEmpty()) throw IllegalArgumentException("Map is non-empty")
        // Java Boolean is a platform type. Both Boolean and Boolean? maps accept true.
        return CollectionsMapBackedSet(backing as MutableMap<E, Boolean>)
    }
}

private fun collectionsRejectMutation(): Nothing = throw UnsupportedOperationException()

private class CollectionsUnmodifiableIterator<E>(private val backing: Iterator<E>) : MutableIterator<E> {
    override fun hasNext(): Boolean = backing.hasNext()
    override fun next(): E = backing.next()
    override fun remove(): Unit = collectionsRejectMutation()
}

private class CollectionsUnmodifiableListIterator<E>(
    private val backing: ListIterator<E>
) : MutableListIterator<E> {
    override fun hasNext(): Boolean = backing.hasNext()
    override fun next(): E = backing.next()
    override fun hasPrevious(): Boolean = backing.hasPrevious()
    override fun previous(): E = backing.previous()
    override fun nextIndex(): Int = backing.nextIndex()
    override fun previousIndex(): Int = backing.previousIndex()
    override fun remove(): Unit = collectionsRejectMutation()
    override fun add(element: E): Unit = collectionsRejectMutation()
    override fun set(element: E): Unit = collectionsRejectMutation()
}

@Suppress("UNCHECKED_CAST")
private fun <E> collectionsUnmodifiableList(backing: List<E>): MutableList<E> =
    if (backing is RandomAccess) CollectionsUnmodifiableRandomAccessList(backing)
    else CollectionsUnmodifiableList(backing)

private class CollectionsUnmodifiableRandomAccessList<E>(
    backing: List<E>
) : CollectionsUnmodifiableList<E>(backing), RandomAccess

private open class CollectionsUnmodifiableList<E>(private val backing: List<E>) : AbstractMutableList<E>() {
    override val size: Int get() = backing.size
    override fun equals(other: Any?): Boolean = other === this || backing == other
    override fun hashCode(): Int = backing.hashCode()
    override fun toString(): String = backing.toString()
    override fun get(index: Int): E = backing[index]
    override fun contains(element: E): Boolean = backing.contains(element)
    override fun containsAll(elements: Collection<E>): Boolean = backing.containsAll(elements)
    override fun isEmpty(): Boolean = backing.isEmpty()
    override fun indexOf(element: E): Int = backing.indexOf(element)
    override fun lastIndexOf(element: E): Int = backing.lastIndexOf(element)
    override fun iterator(): MutableIterator<E> = CollectionsUnmodifiableIterator(backing.iterator())
    override fun listIterator(): MutableListIterator<E> = CollectionsUnmodifiableListIterator(backing.listIterator())
    override fun listIterator(index: Int): MutableListIterator<E> = CollectionsUnmodifiableListIterator(backing.listIterator(index))
    override fun subList(fromIndex: Int, toIndex: Int): MutableList<E> =
        collectionsUnmodifiableList(backing.subList(fromIndex, toIndex))

    // Reject even no-op mutations, and keep iterators/subviews behind the same boundary.
    override fun add(element: E): Boolean = collectionsRejectMutation()
    override fun add(index: Int, element: E): Unit = collectionsRejectMutation()
    override fun addAll(elements: Collection<E>): Boolean = collectionsRejectMutation()
    override fun addAll(index: Int, elements: Collection<E>): Boolean = collectionsRejectMutation()
    override fun set(index: Int, element: E): E = collectionsRejectMutation()
    override fun removeAt(index: Int): E = collectionsRejectMutation()
    override fun remove(element: E): Boolean = collectionsRejectMutation()
    override fun removeAll(elements: Collection<E>): Boolean = collectionsRejectMutation()
    override fun retainAll(elements: Collection<E>): Boolean = collectionsRejectMutation()
    override fun clear(): Unit = collectionsRejectMutation()
}

private class CollectionsUnmodifiableCollection<E>(
    private val backing: Collection<E>
) : AbstractMutableCollection<E>() {
    override val size: Int get() = backing.size
    override fun contains(element: E): Boolean = backing.contains(element)
    override fun containsAll(elements: Collection<E>): Boolean = backing.containsAll(elements)
    override fun isEmpty(): Boolean = backing.isEmpty()
    override fun iterator(): MutableIterator<E> = CollectionsUnmodifiableIterator(backing.iterator())
    override fun add(element: E): Boolean = collectionsRejectMutation()
    override fun addAll(elements: Collection<E>): Boolean = collectionsRejectMutation()
    override fun remove(element: E): Boolean = collectionsRejectMutation()
    override fun removeAll(elements: Collection<E>): Boolean = collectionsRejectMutation()
    override fun retainAll(elements: Collection<E>): Boolean = collectionsRejectMutation()
    override fun clear(): Unit = collectionsRejectMutation()
}

private class CollectionsUnmodifiableSet<E>(private val backing: Set<E>) : AbstractMutableSet<E>() {
    override val size: Int get() = backing.size
    override fun equals(other: Any?): Boolean = other === this || backing == other
    override fun hashCode(): Int = backing.hashCode()
    override fun toString(): String = backing.toString()
    override fun contains(element: E): Boolean = backing.contains(element)
    override fun containsAll(elements: Collection<E>): Boolean = backing.containsAll(elements)
    override fun isEmpty(): Boolean = backing.isEmpty()
    override fun iterator(): MutableIterator<E> = CollectionsUnmodifiableIterator(backing.iterator())
    override fun add(element: E): Boolean = collectionsRejectMutation()
    override fun addAll(elements: Collection<E>): Boolean = collectionsRejectMutation()
    override fun remove(element: E): Boolean = collectionsRejectMutation()
    override fun removeAll(elements: Collection<E>): Boolean = collectionsRejectMutation()
    override fun retainAll(elements: Collection<E>): Boolean = collectionsRejectMutation()
    override fun clear(): Unit = collectionsRejectMutation()
}

private class CollectionsUnmodifiableEntry<K, V>(
    private val backing: Map.Entry<K, V>
) : MutableMap.MutableEntry<K, V> {
    override val key: K get() = backing.key
    override val value: V get() = backing.value
    override fun setValue(newValue: V): V = collectionsRejectMutation()
    override fun equals(other: Any?): Boolean =
        other === this || (other is Map.Entry<*, *> && key == other.key && value == other.value)
    override fun hashCode(): Int = backing.hashCode()
    override fun toString(): String = backing.toString()
}

private class CollectionsUnmodifiableEntries<K, V>(
    private val backing: Set<Map.Entry<K, V>>
) : AbstractMutableSet<MutableMap.MutableEntry<K, V>>() {
    override val size: Int get() = backing.size
    override fun contains(element: MutableMap.MutableEntry<K, V>): Boolean =
        backing.contains(CollectionsUnmodifiableEntry(element))
    override fun containsAll(elements: Collection<MutableMap.MutableEntry<K, V>>): Boolean {
        for (element in elements) if (!contains(element)) return false
        return true
    }
    @Suppress("UNCHECKED_CAST")
    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is Set<*> || other.size != size) return false
        for (element in other) {
            if (element !is Map.Entry<*, *>) return false
            // Protect every queried entry while preserving the backing set's membership policy.
            if (!backing.contains(CollectionsUnmodifiableEntry(element as Map.Entry<K, V>))) return false
        }
        return true
    }
    override fun iterator(): MutableIterator<MutableMap.MutableEntry<K, V>> {
        val iterator = backing.iterator()
        return object : MutableIterator<MutableMap.MutableEntry<K, V>> {
            override fun hasNext(): Boolean = iterator.hasNext()
            override fun next(): MutableMap.MutableEntry<K, V> = CollectionsUnmodifiableEntry(iterator.next())
            override fun remove(): Unit = collectionsRejectMutation()
        }
    }
    override fun add(element: MutableMap.MutableEntry<K, V>): Boolean = collectionsRejectMutation()
    override fun addAll(elements: Collection<MutableMap.MutableEntry<K, V>>): Boolean = collectionsRejectMutation()
    override fun remove(element: MutableMap.MutableEntry<K, V>): Boolean = collectionsRejectMutation()
    override fun removeAll(elements: Collection<MutableMap.MutableEntry<K, V>>): Boolean = collectionsRejectMutation()
    override fun retainAll(elements: Collection<MutableMap.MutableEntry<K, V>>): Boolean = collectionsRejectMutation()
    override fun clear(): Unit = collectionsRejectMutation()
}

private class CollectionsUnmodifiableMap<K, V>(private val backing: Map<out K, V>) : AbstractMutableMap<K, V>() {
    override val size: Int get() = backing.size
    override fun equals(other: Any?): Boolean = other === this || backing == other
    override fun hashCode(): Int = backing.hashCode()
    override fun toString(): String = backing.toString()
    // The projection permits widening the key type at the Java facade boundary.
    // Read-only queries are safe after erasing that projection, as on the JVM.
    @Suppress("UNCHECKED_CAST")
    override fun get(key: K): V? = (backing as Map<K, V>)[key]
    @Suppress("UNCHECKED_CAST")
    override fun containsKey(key: K): Boolean = (backing as Map<K, V>).containsKey(key)
    override fun containsValue(value: V): Boolean = backing.containsValue(value)
    override fun isEmpty(): Boolean = backing.isEmpty()
    override val keys: MutableSet<K> get() = CollectionsUnmodifiableSet(backing.keys)
    override val values: MutableCollection<V> get() = CollectionsUnmodifiableCollection(backing.values)
    override val entries: MutableSet<MutableMap.MutableEntry<K, V>> get() = CollectionsUnmodifiableEntries(backing.entries)
    override fun put(key: K, value: V): V? = collectionsRejectMutation()
    override fun putAll(from: Map<out K, V>): Unit = collectionsRejectMutation()
    override fun remove(key: K): V? = collectionsRejectMutation()
    override fun clear(): Unit = collectionsRejectMutation()
}

private class CollectionsMapBackedSet<E>(private val backing: MutableMap<E, Boolean>) : AbstractMutableSet<E>() {
    private val keySet: MutableSet<E> = backing.keys
    override val size: Int get() = backing.size
    override fun isEmpty(): Boolean = backing.isEmpty()
    override fun contains(element: E): Boolean = backing.containsKey(element)
    override fun containsAll(elements: Collection<E>): Boolean = keySet.containsAll(elements)
    override fun iterator(): MutableIterator<E> = keySet.iterator()
    override fun add(element: E): Boolean = backing.put(element, true) == null
    override fun remove(element: E): Boolean = backing.remove(element) != null
    override fun removeAll(elements: Collection<E>): Boolean = keySet.removeAll(elements)
    override fun retainAll(elements: Collection<E>): Boolean = keySet.retainAll(elements)
    override fun clear() = backing.clear()
    override fun equals(other: Any?): Boolean = other === this || keySet == other
    override fun hashCode(): Int = keySet.hashCode()
    override fun toString(): String = keySet.toString()
}
