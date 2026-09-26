package kotlin.collections

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_mutable_list_set")
private external fun <E> __kkMutableListSet(list: MutableList<E>, index: Int, element: E): E

@KsSymbolName("__kk_mutable_list_add")
private external fun <E> __kkMutableListAdd(list: MutableList<E>, element: E): Boolean

@KsSymbolName("__kk_mutable_list_add_at")
private external fun <E> __kkMutableListAddAt(list: MutableList<E>, index: Int, element: E)

@KsSymbolName("__kk_mutable_list_addAll")
private external fun <E> __kkMutableListAddAll(
    list: MutableList<E>,
    elements: Collection<out E>
): Boolean

@KsSymbolName("__kk_mutable_list_removeAt")
private external fun <E> __kkMutableListRemoveAt(list: MutableList<E>, index: Int): E

@KsSymbolName("__kk_mutable_list_remove")
private external fun <E> __kkMutableListRemove(list: MutableList<E>, element: E): Boolean

@KsSymbolName("__kk_mutable_list_clear")
private external fun <E> __kkMutableListClear(list: MutableList<E>)

@KsSymbolName("__kk_mutable_list_removeAll")
private external fun <E> __kkMutableListRemoveAll(
    list: MutableList<E>,
    elements: Collection<out E>
): Boolean

@KsSymbolName("__kk_mutable_list_retainAll")
private external fun <E> __kkMutableListRetainAll(
    list: MutableList<E>,
    elements: Collection<out E>
): Boolean

// KSP-1503: the MutableList mutation surface is source-backed. The private
// externals above are the demoted runtime bridges; keeping the bridge calls in
// default interface bodies preserves the runtime-backed behavior for erased
// MutableList receivers without synthetic member declarations.
// KSP-705: the addAll members stay `external` declarations bound directly to
// their demoted bridges, matching the MutableCollection.addAll migration.
// KSP-700: list-iterator overrides are source-backed to keep the covariant
// return type visible to inherited abstract-member checks.
public interface MutableList<E> : List<E>, MutableCollection<E> {
    @IgnorableReturnValue
    public operator fun set(index: Int, element: E): E =
        __kkMutableListSet(this, index, element)

    @IgnorableReturnValue
    public fun add(element: E): Boolean =
        __kkMutableListAdd(this, element)

    public fun add(index: Int, element: E) {
        __kkMutableListAddAt(this, index, element)
    }

    /**
     * Adds all elements of [elements] to the end of this mutable list.
     */
    @KsSymbolName("__kk_mutable_list_addAll")
    @IgnorableReturnValue
    public override external fun addAll(elements: Collection<out E>): Boolean

    /**
     * Inserts all elements of [elements] starting at [index].
     */
    @KsSymbolName("__kk_mutable_list_addAll_at")
    @IgnorableReturnValue
    public external fun addAll(index: Int, elements: Collection<out E>): Boolean

    @IgnorableReturnValue
    public fun removeAt(index: Int): E =
        __kkMutableListRemoveAt(this, index)

    public fun clear() {
        __kkMutableListClear(this)
    }

    @IgnorableReturnValue
    public fun removeAll(elements: Collection<out E>): Boolean =
        __kkMutableListRemoveAll(this, elements)

    @IgnorableReturnValue
    public fun retainAll(elements: Collection<out E>): Boolean =
        __kkMutableListRetainAll(this, elements)

    public operator fun plusAssign(element: E) {
        __kkMutableListAdd(this, element)
    }

    public operator fun plusAssign(elements: Collection<out E>) {
        __kkMutableListAddAll(this, elements)
    }

    public operator fun minusAssign(element: E) {
        __kkMutableListRemove(this, element)
    }

    public operator fun minusAssign(elements: Collection<out E>) {
        __kkMutableListRemoveAll(this, elements)
    }

    @KsSymbolName("kk_list_iterator")
    public override fun listIterator(): MutableListIterator<E>

    @KsSymbolName("kk_list_iterator_at")
    public override fun listIterator(index: Int): MutableListIterator<E>
}

/**
 * Creates a mutable list whose elements are produced in ascending index order.
 */
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
