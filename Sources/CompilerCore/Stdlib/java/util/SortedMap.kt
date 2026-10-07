/*
 * KUU-1361: JVM java.util.SortedMap parity for the bundled stdlib.
 */

package java.util

import kotlin.collections.MutableMap
import kotlin.internal.KsSymbolName

// Members are bodiless @KsSymbolName declarations — see SortedSet.kt for the
// rationale.

/**
 * A [MutableMap] that keeps its entries ordered by key — `java.util.SortedMap`.
 */
public interface SortedMap<K, V> : MutableMap<K, V> {
    /** The comparator used to order keys, or `null` for natural ordering. */
    @KsSymbolName("__kk_sorted_map_comparator")
    public fun comparator(): Comparator<in K>?

    /** The lowest key; throws `NoSuchElementException` when the map is empty. */
    @KsSymbolName("__kk_sorted_map_first_key")
    public fun firstKey(): K

    /** The highest key; throws `NoSuchElementException` when the map is empty. */
    @KsSymbolName("__kk_sorted_map_last_key")
    public fun lastKey(): K
}
