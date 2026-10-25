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

    /** A live view of the entries with keys strictly below [toKey]. */
    @KsSymbolName("__kk_sorted_map_head_map")
    public fun headMap(toKey: K): SortedMap<K, V>

    /** A live view of the entries with keys at or above [fromKey]. */
    @KsSymbolName("__kk_sorted_map_tail_map")
    public fun tailMap(fromKey: K): SortedMap<K, V>

    /** A live view starting at [fromKey] and ending before [toKey]. */
    @KsSymbolName("__kk_sorted_map_sub_map")
    public fun subMap(fromKey: K, toKey: K): SortedMap<K, V>
}
