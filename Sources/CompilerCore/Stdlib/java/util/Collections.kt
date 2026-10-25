package java.util

import kotlin.comparisons.compareValuesUnchecked

public object Collections {
    @Suppress("UNCHECKED_CAST")
    public fun <T> emptyList(): MutableList<T> = collectionsEmptyList as MutableList<T>

    @Suppress("UNCHECKED_CAST")
    public fun <T> emptySet(): MutableSet<T> = collectionsEmptySet as MutableSet<T>

    @Suppress("UNCHECKED_CAST")
    public fun <K, V> emptyMap(): MutableMap<K, V> = collectionsEmptyMap as MutableMap<K, V>

    public fun <T> singletonList(element: T): MutableList<T> =
        collectionsUnmodifiableList(kotlin.collections.listOf(element))

    public fun <T> singleton(element: T): MutableSet<T> =
        CollectionsUnmodifiableSet(kotlin.collections.setOf(element))

    public fun <K, V> singletonMap(key: K, value: V): MutableMap<K, V> =
        CollectionsUnmodifiableMap(kotlin.collections.mapOf(key to value))

    public fun <T> nCopies(count: Int, element: T): MutableList<T> {
        if (count < 0) throw IllegalArgumentException("List length = $count")
        return collectionsUnmodifiableList(CollectionsCopiesBacking(count, element))
    }

    public fun <T> emptyIterator(): MutableIterator<T> =
        CollectionsUnmodifiableIterator(kotlin.collections.emptyList<T>().iterator())

    public fun <T> emptyListIterator(): MutableListIterator<T> =
        CollectionsUnmodifiableListIterator(kotlin.collections.emptyList<T>().listIterator())

    public fun <T> emptyEnumeration(): Enumeration<T> = object : Enumeration<T> {
        override fun hasMoreElements(): Boolean = false
        override fun nextElement(): T = throw NoSuchElementException()
    }

    public fun <T> reverseOrder(): Comparator<T> = Comparator { first, second ->
        collectionsNaturalCompare(second, first)
    }

    public fun <T> reverseOrder(comparator: Comparator<in T>?): Comparator<T> {
        if (comparator == null) return reverseOrder()
        return Comparator { first, second -> comparator.compare(second, first) }
    }

    public fun <T> sort(list: MutableList<T>?) {
        sort(list, null)
    }

    public fun <T> sort(list: MutableList<T>?, comparator: Comparator<in T>?) {
        val target = list!!
        target.sortWith(comparator ?: collectionsNaturalComparator())
    }

    public fun <T> shuffle(list: MutableList<T>?) {
        list!!.shuffle()
    }

    public fun <T> shuffle(list: MutableList<T>?, random: Random?) {
        list!!.shuffle(random!!.delegate)
    }

    public fun <T> binarySearch(list: List<T>?, key: T): Int =
        binarySearch(list, key, null)

    public fun <T> binarySearch(list: List<T>?, key: T, comparator: Comparator<in T>?): Int {
        val target = list!!
        var low = 0
        var high = target.size - 1
        val ordering = comparator ?: collectionsNaturalComparator()
        while (low <= high) {
            val middle = (low + high) ushr 1
            val comparison = ordering.compare(target[middle], key)
            if (comparison < 0) low = middle + 1
            else if (comparison > 0) high = middle - 1
            else return middle
        }
        return -(low + 1)
    }

    public fun <T> min(collection: Collection<T>?, comparator: Comparator<in T>?): T =
        collectionsMinOrMax(collection!!, comparator, findMaximum = false)

    public fun <T> min(collection: Collection<T>?): T = min(collection, null)

    public fun <T> max(collection: Collection<T>?, comparator: Comparator<in T>?): T =
        collectionsMinOrMax(collection!!, comparator, findMaximum = true)

    public fun <T> max(collection: Collection<T>?): T = max(collection, null)

    public fun frequency(collection: Collection<*>?, element: Any?): Int {
        var count = 0
        for (candidate in collection!!) if (candidate == element) count++
        return count
    }

    public fun disjoint(first: Collection<*>?, second: Collection<*>?): Boolean {
        val left = first!!
        val right = second!!
        val smaller = if (left.size <= right.size) left else right
        val larger = if (left.size <= right.size) right else left
        for (element in smaller) if (larger.contains(element)) return false
        return true
    }

    public fun <T> fill(list: MutableList<T>?, element: T) {
        val target = list!!
        var index = 0
        while (index < target.size) {
            target[index] = element
            index++
        }
    }

    public fun <T> copy(destination: MutableList<in T>?, source: List<out T>?) {
        val target = destination!!
        val values = source!!
        if (values.size > target.size) throw IndexOutOfBoundsException("Source does not fit in dest")
        var index = 0
        while (index < values.size) {
            target[index] = values[index]
            index++
        }
    }

    @Suppress("UNCHECKED_CAST")
    public fun swap(list: MutableList<*>?, first: Int, second: Int) {
        val target = list!! as MutableList<Any?>
        if (first == second) return
        val temporary = target[first]
        target[first] = target[second]
        target[second] = temporary
    }

    @Suppress("UNCHECKED_CAST")
    public fun rotate(list: MutableList<*>?, distance: Int) {
        val target = list!! as MutableList<Any?>
        val count = target.size
        if (count <= 1) return
        var shift = distance % count
        if (shift < 0) shift += count
        if (shift == 0) return
        val values = ArrayList<Any?>(count)
        var index = 0
        while (index < count) {
            var sourceIndex = index - shift
            if (sourceIndex < 0) sourceIndex += count
            values.add(target[sourceIndex])
            index++
        }
        index = 0
        while (index < count) {
            target[index] = values[index]
            index++
        }
    }

    @Suppress("UNCHECKED_CAST")
    public fun reverse(list: MutableList<*>?) {
        val target = list!! as MutableList<Any?>
        var left = 0
        var right = target.size - 1
        while (left < right) {
            val temporary = target[left]
            target[left] = target[right]
            target[right] = temporary
            left++
            right--
        }
    }

    public fun <T> replaceAll(list: MutableList<T>?, oldValue: T, newValue: T): Boolean {
        val target = list!!
        var changed = false
        var index = 0
        while (index < target.size) {
            if (target[index] == oldValue) {
                target[index] = newValue
                changed = true
            }
            index++
        }
        return changed
    }

    public fun indexOfSubList(source: List<*>?, target: List<*>?): Int {
        val values = source!!
        val pattern = target!!
        if (pattern.isEmpty()) return 0
        var start = 0
        while (start <= values.size - pattern.size) {
            var offset = 0
            while (offset < pattern.size && values[start + offset] == pattern[offset]) offset++
            if (offset == pattern.size) return start
            start++
        }
        return -1
    }

    public fun lastIndexOfSubList(source: List<*>?, target: List<*>?): Int {
        val values = source!!
        val pattern = target!!
        if (pattern.isEmpty()) return values.size
        var start = values.size - pattern.size
        while (start >= 0) {
            var offset = 0
            while (offset < pattern.size && values[start + offset] == pattern[offset]) offset++
            if (offset == pattern.size) return start
            start--
        }
        return -1
    }

    public fun <T> addAll(collection: MutableCollection<T>?, vararg elements: T): Boolean {
        val target = collection!!
        var modified = false
        for (element in elements) {
            if (target.add(element)) modified = true
        }
        return modified
    }

    public fun <T> enumeration(collection: Collection<T>?): Enumeration<T> =
        CollectionsIteratorEnumeration(collection!!.iterator())

    public fun <T> list(enumeration: Enumeration<T>?): ArrayList<T> {
        val result = ArrayList<T>()
        val source = enumeration!!
        while (source.hasMoreElements()) result.add(source.nextElement())
        return result
    }

    public fun <T> checkedList(list: MutableList<T>?, type: Class<T>?): MutableList<T> =
        collectionsCheckedList(list!!, type!!)

    public fun <T> synchronizedList(list: MutableList<T>?): MutableList<T> =
        collectionsSynchronizedList(list!!)

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

private val collectionsEmptyList: MutableList<Any?> =
    collectionsUnmodifiableList(kotlin.collections.emptyList())
private val collectionsEmptySet: MutableSet<Any?> = CollectionsUnmodifiableSet(kotlin.collections.emptySet())
private val collectionsEmptyMap: MutableMap<Any?, Any?> = CollectionsUnmodifiableMap(kotlin.collections.emptyMap())

private fun <T> collectionsNaturalComparator(): Comparator<T> = Comparator { first, second ->
    collectionsNaturalCompare(first, second)
}

private fun <T> collectionsNaturalCompare(first: T, second: T): Int {
    if (first == null || second == null) throw NullPointerException()
    return compareValuesUnchecked(first, second)
}

private fun <T> collectionsMinOrMax(
    collection: Collection<T>,
    comparator: Comparator<in T>?,
    findMaximum: Boolean
): T {
    val iterator = collection.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var selected = iterator.next()
    val ordering = comparator ?: collectionsNaturalComparator()
    while (iterator.hasNext()) {
        val candidate = iterator.next()
        val comparison = ordering.compare(candidate, selected)
        if ((findMaximum && comparison > 0) || (!findMaximum && comparison < 0)) selected = candidate
    }
    return selected
}

private class CollectionsCopiesBacking<E>(private val count: Int, private val element: E) : AbstractList<E>() {
    override val size: Int get() = count
    override fun get(index: Int): E {
        if (index < 0 || index >= count) throw IndexOutOfBoundsException("Index: $index, Size: $count")
        return element
    }
}

private class CollectionsIteratorEnumeration<E>(private val iterator: Iterator<E>) : Enumeration<E> {
    override fun hasMoreElements(): Boolean = iterator.hasNext()
    override fun nextElement(): E = iterator.next()
}

private fun <E> collectionsCheckElementType(element: E, type: Class<E>) {
    if (element != null && !type.isInstance(element)) throw ClassCastException()
}

private fun <E> collectionsCheckedList(backing: MutableList<E>, type: Class<E>): MutableList<E> =
    if (backing is RandomAccess) CollectionsCheckedRandomAccessList(backing, type)
    else CollectionsCheckedList(backing, type)

private open class CollectionsCheckedList<E>(
    private val backing: MutableList<E>,
    private val type: Class<E>
) : AbstractMutableList<E>() {
    override val size: Int get() = backing.size
    override fun get(index: Int): E = backing[index]

    override fun set(index: Int, element: E): E {
        collectionsCheckElementType(element, type)
        return backing.set(index, element)
    }

    override fun add(index: Int, element: E) {
        collectionsCheckElementType(element, type)
        backing.add(index, element)
    }

    override fun add(element: E): Boolean {
        collectionsCheckElementType(element, type)
        return backing.add(element)
    }

    override fun addAll(elements: Collection<E>): Boolean {
        for (element in elements) collectionsCheckElementType(element, type)
        return backing.addAll(elements)
    }

    override fun addAll(index: Int, elements: Collection<E>): Boolean {
        for (element in elements) collectionsCheckElementType(element, type)
        return backing.addAll(index, elements)
    }

    override fun removeAt(index: Int): E = backing.removeAt(index)
    override fun remove(element: E): Boolean = backing.remove(element)
    override fun removeAll(elements: Collection<E>): Boolean = backing.removeAll(elements)
    override fun retainAll(elements: Collection<E>): Boolean = backing.retainAll(elements)
    override fun clear() = backing.clear()
    override fun iterator(): MutableIterator<E> = listIterator()
    override fun listIterator(): MutableListIterator<E> = CollectionsCheckedListIterator(backing.listIterator(), type)
    override fun listIterator(index: Int): MutableListIterator<E> =
        CollectionsCheckedListIterator(backing.listIterator(index), type)
    override fun subList(fromIndex: Int, toIndex: Int): MutableList<E> =
        collectionsCheckedList(backing.subList(fromIndex, toIndex), type)
}

private class CollectionsCheckedRandomAccessList<E>(backing: MutableList<E>, type: Class<E>) :
    CollectionsCheckedList<E>(backing, type), RandomAccess

private class CollectionsCheckedListIterator<E>(
    private val backing: MutableListIterator<E>,
    private val type: Class<E>
) : MutableListIterator<E> {
    override fun hasNext(): Boolean = backing.hasNext()
    override fun next(): E = backing.next()
    override fun hasPrevious(): Boolean = backing.hasPrevious()
    override fun previous(): E = backing.previous()
    override fun nextIndex(): Int = backing.nextIndex()
    override fun previousIndex(): Int = backing.previousIndex()
    override fun remove() = backing.remove()
    override fun add(element: E) {
        collectionsCheckElementType(element, type)
        backing.add(element)
    }
    override fun set(element: E) {
        collectionsCheckElementType(element, type)
        backing.set(element)
    }
}

private fun <E> collectionsSynchronizedList(backing: MutableList<E>): MutableList<E> =
    if (backing is RandomAccess) CollectionsSynchronizedRandomAccessList(backing, null)
    else CollectionsSynchronizedList(backing, null)

private open class CollectionsSynchronizedList<E>(
    private val backing: MutableList<E>,
    mutex: Any?
) : AbstractMutableList<E>() {
    private val lock: Any = mutex ?: this

    override val size: Int get() = synchronized(lock) { backing.size }
    override fun get(index: Int): E = synchronized(lock) { backing[index] }
    override fun set(index: Int, element: E): E = synchronized(lock) { backing.set(index, element) }
    override fun add(index: Int, element: E) = synchronized(lock) { backing.add(index, element) }
    override fun add(element: E): Boolean = synchronized(lock) { backing.add(element) }
    override fun addAll(elements: Collection<E>): Boolean = synchronized(lock) { backing.addAll(elements) }
    override fun addAll(index: Int, elements: Collection<E>): Boolean =
        synchronized(lock) { backing.addAll(index, elements) }
    override fun removeAt(index: Int): E = synchronized(lock) { backing.removeAt(index) }
    override fun remove(element: E): Boolean = synchronized(lock) { backing.remove(element) }
    override fun removeAll(elements: Collection<E>): Boolean = synchronized(lock) { backing.removeAll(elements) }
    override fun retainAll(elements: Collection<E>): Boolean = synchronized(lock) { backing.retainAll(elements) }
    override fun clear() = synchronized(lock) { backing.clear() }
    override fun isEmpty(): Boolean = synchronized(lock) { backing.isEmpty() }
    override fun contains(element: E): Boolean = synchronized(lock) { backing.contains(element) }
    override fun containsAll(elements: Collection<E>): Boolean = synchronized(lock) { backing.containsAll(elements) }
    override fun equals(other: Any?): Boolean = synchronized(lock) { other === this || backing == other }
    override fun hashCode(): Int = synchronized(lock) { backing.hashCode() }
    override fun toString(): String = synchronized(lock) { backing.toString() }
    override fun iterator(): MutableIterator<E> = listIterator()
    override fun listIterator(): MutableListIterator<E> = synchronized(lock) {
        CollectionsSynchronizedListIterator(backing.listIterator(), lock)
    }
    override fun listIterator(index: Int): MutableListIterator<E> = synchronized(lock) {
        CollectionsSynchronizedListIterator(backing.listIterator(index), lock)
    }
    override fun subList(fromIndex: Int, toIndex: Int): MutableList<E> = synchronized(lock) {
        val view = backing.subList(fromIndex, toIndex)
        if (view is RandomAccess) CollectionsSynchronizedRandomAccessList(view, lock)
        else CollectionsSynchronizedList(view, lock)
    }
}

private class CollectionsSynchronizedRandomAccessList<E>(backing: MutableList<E>, lock: Any?) :
    CollectionsSynchronizedList<E>(backing, lock), RandomAccess

private class CollectionsSynchronizedListIterator<E>(
    private val backing: MutableListIterator<E>,
    private val lock: Any
) : MutableListIterator<E> {
    override fun hasNext(): Boolean = synchronized(lock) { backing.hasNext() }
    override fun next(): E = synchronized(lock) { backing.next() }
    override fun hasPrevious(): Boolean = synchronized(lock) { backing.hasPrevious() }
    override fun previous(): E = synchronized(lock) { backing.previous() }
    override fun nextIndex(): Int = synchronized(lock) { backing.nextIndex() }
    override fun previousIndex(): Int = synchronized(lock) { backing.previousIndex() }
    override fun remove() = synchronized(lock) { backing.remove() }
    override fun add(element: E) = synchronized(lock) { backing.add(element) }
    override fun set(element: E) = synchronized(lock) { backing.set(element) }
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
