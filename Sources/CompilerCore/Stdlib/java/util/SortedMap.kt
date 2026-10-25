package java.util

import kotlin.collections.MutableMap
import kotlin.internal.KsSymbolName

// Members are bodiless @KsSymbolName declarations — see SortedSet.kt for the
// rationale.

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

    /** A live view starting at [fromKey] and ending before [toKey]. */
    @KsSymbolName("__kk_sorted_map_sub_map")
    public fun subMap(fromKey: K, toKey: K): SortedMap<K, V>
}
