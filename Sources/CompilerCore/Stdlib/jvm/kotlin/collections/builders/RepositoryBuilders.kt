package kotlin.collections.builders

import kotlin.jvm.internal.*
import kotlin.jvm.internal.markers.*

internal class RepositoryBuilderState: java.io.Serializable {
    var frozen: Boolean = false
    var modification: Int = 0
    fun checkModification(expected: Int) { if (modification != expected) throw __jvmBuilderConcurrentModificationFailure(null) }
    fun checkMutable() { if (frozen) throw UnsupportedOperationException() }
}

// Views and iterators share the same completion state as their root builder.
internal class RepositoryBuilderIterator<E>(private val state: RepositoryBuilderState, private val source: MutableIterator<E>, private val entries: Boolean): MutableIterator<E>, KMutableIterator {
    private var expectedModification = state.modification
    private var canRemove = false
    override fun hasNext(): Boolean = source.hasNext()
    override fun next(): E {
        state.checkModification(expectedModification)
        val value = source.next()
        canRemove = true
        if (entries) return RepositoryBuilderEntry<Any?, Any?>(state, value as java.util.MapEntry<Any?, Any?>) as E
        return value
    }
    override fun remove() {
        state.checkModification(expectedModification)
        if (!canRemove) throw IllegalStateException()
        state.checkMutable()
        source.remove()
        state.modification++
        expectedModification = state.modification
        canRemove = false
    }
}
internal class RepositoryBuilderListIterator<E>(private val state: RepositoryBuilderState, private val source: java.util.ListIterator<E>): java.util.ListIterator<E>, KMutableIterator {
    override fun hasNext(): Boolean = source.hasNext()
    private var expectedModification = state.modification
    private var canModify = false
    override fun next(): E { state.checkModification(expectedModification); val value = source.next(); canModify = true; return value }
    override fun hasPrevious(): Boolean = source.hasPrevious()
    override fun previous(): E { state.checkModification(expectedModification); val value = source.previous(); canModify = true; return value }
    override fun nextIndex(): Int = source.nextIndex()
    override fun previousIndex(): Int = source.previousIndex()
    override fun add(element: E) {
        state.checkModification(expectedModification); state.checkMutable(); source.add(element)
        state.modification++; expectedModification = state.modification; canModify = false
    }
    override fun set(element: E) {
        state.checkModification(expectedModification)
        if (!canModify) throw IllegalStateException()
        state.checkMutable(); source.set(element)
    }
    override fun remove() {
        state.checkModification(expectedModification)
        if (!canModify) throw IllegalStateException()
        state.checkMutable(); source.remove()
        state.modification++; expectedModification = state.modification; canModify = false
    }
}
internal open class RepositoryBuilderCollection<E>(protected val state: RepositoryBuilderState, protected val source: Collection<E>, private val entries: Boolean = false): java.util.AbstractCollection<E>(), MutableCollection<E>, KMutableCollection {
    override val size: Int get() = source.size
    override fun isEmpty(): Boolean = source.isEmpty()
    override fun contains(element: E): Boolean = source.contains(element)
    override fun containsAll(elements: Collection<E>): Boolean = source.containsAll(elements)
    override fun iterator(): MutableIterator<E> = RepositoryBuilderIterator(state, source.iterator() as MutableIterator<E>, entries)
    override fun add(element: E): Boolean { throw UnsupportedOperationException() }
    override fun remove(element: E): Boolean { state.checkMutable(); val changed = __jvmCollectionRemove(source, element); if (changed) state.modification++; return changed }
    override fun clear() { state.checkMutable(); __jvmCollectionClear(source); state.modification++ }
    override fun addAll(elements: Collection<E>): Boolean { throw UnsupportedOperationException() }
    override fun removeAll(elements: Collection<E>): Boolean { state.checkMutable(); val changed = __jvmCollectionRemoveAll(source, elements); if (changed) state.modification++; return changed }
    override fun retainAll(elements: Collection<E>): Boolean { state.checkMutable(); val changed = __jvmCollectionRetainAll(source, elements); if (changed) state.modification++; return changed }
}
internal class RepositoryBuilderSet<E>(state: RepositoryBuilderState, source: Collection<E>, entries: Boolean = false): RepositoryBuilderCollection<E>(state, source, entries), MutableSet<E>, KMutableSet {
    override fun equals(other: Any?): Boolean = source == other
    override fun hashCode(): Int = source.hashCode()
}
internal class RepositoryBuilderEntry<K, V>(private val state: RepositoryBuilderState, private val source: java.util.MapEntry<K, V>): java.util.MapEntry<K, V> {
    private val expectedModification = state.modification
    private fun checkModification() {
        if (state.modification != expectedModification) throw __jvmBuilderConcurrentModificationFailure("The backing map has been modified after this entry was obtained.")
    }
    override fun getKey(): K { checkModification(); return source.getKey() }
    override fun getValue(): V { checkModification(); return source.getValue() }
    override fun setValue(value: V): V { checkModification(); state.checkMutable(); return source.setValue(value) }
    override fun equals(other: Any?): Boolean {
        if (other is java.util.MapEntry<*, *>) return other.getKey() == getKey() && other.getValue() == getValue()
        return false
    }
    override fun hashCode(): Int { checkModification(); return source.hashCode() }
    override fun toString(): String { checkModification(); return source.toString() }
}
internal class RepositoryListBuilder<E>(private val state: RepositoryBuilderState, private val source: MutableList<E>): java.util.AbstractList<E>(), MutableList<E>, KMutableList, java.util.RandomAccess, java.io.Serializable {
    constructor(capacity: Int): this(RepositoryBuilderState(), __jvmNewListCapacity<E>(capacity))
    override val size: Int get() = source.size
    override fun isEmpty(): Boolean = source.isEmpty()
    override fun contains(element: E): Boolean = source.contains(element)
    override fun containsAll(elements: Collection<E>): Boolean = source.containsAll(elements)
    override fun get(index: Int): E = source[index]
    override fun set(index: Int, element: E): E { state.checkMutable(); return source.set(index, element) }
    override fun add(element: E): Boolean { state.checkMutable(); val changed = source.add(element); state.modification++; return changed }
    override fun add(index: Int, element: E) { state.checkMutable(); __jvmListAdd(source, index, element); state.modification++ }
    override fun remove(element: E): Boolean { state.checkMutable(); val changed = source.remove(element); if (changed) state.modification++; return changed }
    @kotlin.jvm.JvmName("remove")
    override fun removeAt(index: Int): E { state.checkMutable(); val removed = source.removeAt(index); state.modification++; return removed }
    override fun clear() { state.checkMutable(); val wasEmpty = source.isEmpty(); source.clear(); if (!wasEmpty) state.modification++ }
    override fun addAll(elements: Collection<E>): Boolean { state.checkMutable(); val changed = __jvmCollectionAddAll(source, elements); state.modification++; return changed }
    override fun addAll(index: Int, elements: Collection<E>): Boolean { state.checkMutable(); val changed = __jvmListAddAll(source, index, elements); state.modification++; return changed }
    override fun removeAll(elements: Collection<E>): Boolean { state.checkMutable(); val changed = __jvmCollectionRemoveAll(source, elements); if (changed) state.modification++; return changed }
    override fun retainAll(elements: Collection<E>): Boolean { state.checkMutable(); val changed = __jvmCollectionRetainAll(source, elements); if (changed) state.modification++; return changed }
    override fun listIterator(): java.util.ListIterator<E> = RepositoryBuilderListIterator(state, __jvmListIterator(source, 0))
    override fun listIterator(index: Int): java.util.ListIterator<E> = RepositoryBuilderListIterator(state, __jvmListIterator(source, index))
    override fun iterator(): MutableIterator<E> = RepositoryBuilderIterator(state, source.iterator() as MutableIterator<E>, false)
    override fun indexOf(element: E): Int = source.indexOf(element)
    override fun lastIndexOf(element: E): Int = source.lastIndexOf(element)
    override fun subList(fromIndex: Int, toIndex: Int): MutableList<E> = RepositoryListBuilder(state, __jvmListSubList(source, fromIndex, toIndex))
    private fun writeReplace(): Any {
        if (!state.frozen) throw __jvmBuilderSerializationFailure("The list cannot be serialized while it is being built.")
        val copy = RepositoryListBuilder(RepositoryBuilderState(), __jvmCopyList(source))
        copy.freeze()
        return copy
    }
    fun freeze() { state.checkMutable(); state.frozen = true }
}
internal class RepositoryMapBuilder<K, V>(capacity: Int): java.util.AbstractMap<K, V>(), MutableMap<K, V>, KMutableMap, java.io.Serializable {
    private val state = RepositoryBuilderState()
    private val source = __jvmNewMapCapacity<K, V>(capacity)
    override val size: Int get() = source.size
    fun size(): Int = source.size
    override fun isEmpty(): Boolean = source.isEmpty()
    override fun containsKey(key: K): Boolean = source.containsKey(key)
    override fun containsValue(value: V): Boolean = source.containsValue(value)
    override fun get(key: K): V? = source[key]
    override fun put(key: K, value: V): V? { state.checkMutable(); val size = source.size; val previous = source.put(key, value); if (source.size != size) state.modification++; return previous }
    override fun set(key: K, value: V) { put(key, value) }
    override fun remove(key: K): V? { state.checkMutable(); val size = source.size; val previous = source.remove(key); if (source.size != size) state.modification++; return previous }
    override fun clear() { state.checkMutable(); source.clear(); state.modification++ }
    fun putAll(values: Map<K, V>) { state.checkMutable(); val size = source.size; __jvmMapPutAll(source, values); if (source.size != size) state.modification++ }
    override val keys: Set<K> get() = RepositoryBuilderSet(state, source.keys)
    override val values: Collection<V> get() = RepositoryBuilderCollection(state, source.values)
    override fun keySet(): Set<K> = keys
    override fun values(): Collection<V> = values
    override fun entrySet(): Set<Any?> = RepositoryBuilderSet<Any?>(state, __jvmMapEntries(source), true)
    private fun writeReplace(): Any {
        if (!state.frozen) throw __jvmBuilderSerializationFailure("The map cannot be serialized while it is being built.")
        return this
    }
    fun freeze() { state.checkMutable(); state.frozen = true }
}
internal object RepositoryEmptyListBuilder {
    val value = RepositoryListBuilder<Any?>(0)
    init { value.freeze() }
}
internal object RepositoryEmptyMapBuilder {
    val value = RepositoryMapBuilder<Any?, Any?>(0)
    init { value.freeze() }
}
