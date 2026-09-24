package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-944/705: source-backed MutableList nominal declaration, addAll members,
// and initializer factory. Other mutation members remain compiler/runtime
// residuals until their dedicated migration tasks land.
// KSP-700: list-iterator overrides are source-backed to keep the covariant
// return type visible to inherited abstract-member checks.
public interface MutableList<E> : List<E>, MutableCollection<E> {
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
