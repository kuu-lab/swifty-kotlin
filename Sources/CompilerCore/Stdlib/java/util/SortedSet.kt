/*
 * KUU-1361: JVM java.util.SortedSet parity for the bundled stdlib.
 */

package java.util

import kotlin.collections.MutableSet
import kotlin.internal.KsSymbolName

// Members are bodiless @KsSymbolName declarations (the MutableMap.remove
// precedent): calls through the interface lower straight to runtime bridges
// that dispatch on the receiver's sorted RuntimeSetBox — no itable lookup is
// involved, so TreeSet boxes work through any static receiver type.

/**
 * A [MutableSet] that keeps its elements ordered — `java.util.SortedSet`.
 */
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
}
