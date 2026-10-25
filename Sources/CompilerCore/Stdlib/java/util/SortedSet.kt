package java.util

import kotlin.collections.MutableSet
import kotlin.internal.KsSymbolName

// Members are bodiless @KsSymbolName declarations (the MutableMap.remove
// precedent): calls through the interface lower straight to runtime bridges
// that dispatch on the receiver's sorted RuntimeSetBox — no itable lookup is
// involved, so TreeSet boxes work through any static receiver type.

public interface SortedSet<E> : MutableSet<E> {
    /** The comparator used to order this set, or `null` for natural ordering. */
    @KsSymbolName("__kk_sorted_set_comparator")
    public fun comparator(): Comparator<in E>?

    /** The lowest element; throws `NoSuchElementException` when the set is empty. */
    @KsSymbolName("__kk_sorted_set_first")
    public fun first(): E

    /** The highest element; throws `NoSuchElementException` when the set is empty. */
    @KsSymbolName("__kk_sorted_set_last")
    public fun last(): E

    /** A live view of the elements strictly below [toElement]. */
    @KsSymbolName("__kk_sorted_set_head_set")
    public fun headSet(toElement: E): SortedSet<E>

    /** A live view of the elements at or above [fromElement]. */
    @KsSymbolName("__kk_sorted_set_tail_set")
    public fun tailSet(fromElement: E): SortedSet<E>

    /** A live view starting at [fromElement] and ending before [toElement]. */
    @KsSymbolName("__kk_sorted_set_sub_set")
    public fun subSet(fromElement: E, toElement: E): SortedSet<E>
}
