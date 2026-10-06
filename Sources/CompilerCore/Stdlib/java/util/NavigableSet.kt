/*
 * KUU-1361: JVM java.util.NavigableSet parity for the bundled stdlib.
 */

package java.util

import kotlin.collections.MutableIterator
import kotlin.internal.KsSymbolName

// Members stay bodiless: interface default bodies dispatch through the
// itable, which runtime-backed boxes do not populate.

/**
 * A [SortedSet] with navigation methods — `java.util.NavigableSet`.
 */
public interface NavigableSet<E> : SortedSet<E> {
    @KsSymbolName("__kk_sorted_set_lower")
    public fun lower(e: E): E?

    @KsSymbolName("__kk_sorted_set_floor")
    public fun floor(e: E): E?

    @KsSymbolName("__kk_sorted_set_ceiling")
    public fun ceiling(e: E): E?

    @KsSymbolName("__kk_sorted_set_higher")
    public fun higher(e: E): E?

    @KsSymbolName("__kk_sorted_set_poll_first")
    public fun pollFirst(): E?

    @KsSymbolName("__kk_sorted_set_poll_last")
    public fun pollLast(): E?

    @KsSymbolName("__kk_sorted_set_descending")
    public fun descendingSet(): NavigableSet<E>

    @KsSymbolName("__kk_sorted_set_descending_iterator")
    public fun descendingIterator(): MutableIterator<E>
}
