package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-705/1503: the mutating members stay `external` declarations bound
// directly to their demoted list-specific runtime bridges, matching the
// MutableCollection migration. Bound this way they keep providing an
// implementation to every concrete MutableList without repeating the ABI
// plumbing, while staying recognizable as runtime bridges — e.g. an
// unqualified `super.removeAll()` call must not treat them as an independent
// Kotlin default competing with a concrete superclass implementation.
// KSP-700: list-iterator overrides are source-backed to keep the covariant
// return type visible to inherited abstract-member checks.
public interface MutableList<E> : List<E>, MutableCollection<E> {
    @KsSymbolName("__kk_mutable_list_set")
    @IgnorableReturnValue
    public external operator fun set(index: Int, element: E): E

    @KsSymbolName("__kk_mutable_list_add")
    @IgnorableReturnValue
    public override external fun add(element: E): Boolean

    @KsSymbolName("__kk_mutable_list_add_at")
    public external fun add(index: Int, element: E): Unit

    @KsSymbolName("__kk_mutable_list_addAll_checked")
    @IgnorableReturnValue
    public override external fun addAll(elements: Collection<out E>): Boolean

    @KsSymbolName("__kk_mutable_list_addAll_at")
    @IgnorableReturnValue
    public external fun addAll(index: Int, elements: Collection<out E>): Boolean

    @KsSymbolName("__kk_mutable_list_removeAt")
    @IgnorableReturnValue
    public external fun removeAt(index: Int): E

    @KsSymbolName("__kk_mutable_list_remove_checked")
    @IgnorableReturnValue
    public override external fun remove(element: E): Boolean

    @KsSymbolName("__kk_mutable_list_clear_checked")
    public override external fun clear(): Unit

    @KsSymbolName("__kk_mutable_list_removeAll_checked")
    @IgnorableReturnValue
    public override external fun removeAll(elements: Collection<out E>): Boolean

    @KsSymbolName("__kk_mutable_list_retainAll_checked")
    @IgnorableReturnValue
    public override external fun retainAll(elements: Collection<out E>): Boolean

    public operator fun plusAssign(element: E) {
        add(element)
    }

    public operator fun plusAssign(elements: Collection<out E>) {
        addAll(elements)
    }

    public operator fun minusAssign(element: E) {
        remove(element)
    }

    public operator fun minusAssign(elements: Collection<out E>) {
        removeAll(elements)
    }

    @KsSymbolName("__kk_mutable_list_listIterator")
    public override fun listIterator(): MutableListIterator<E>

    @KsSymbolName("kk_list_iterator_at")
    public override fun listIterator(index: Int): MutableListIterator<E>

    @KsSymbolName("kk_list_subList")
    public override external fun subList(fromIndex: Int, toIndex: Int): MutableList<E>
}

public inline fun <T> MutableList(size: Int, init: (index: Int) -> T): MutableList<T> {
    if (size < 0) throw IllegalArgumentException("Illegal Capacity: $size")

    val list = mutableListOf<T>()
    var index = 0
    while (index < size) {
        list.add(init(index))
        index++
    }
    return list
}
