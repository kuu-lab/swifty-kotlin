package java.util

import kotlin.collections.MutableMap
import kotlin.internal.KsSymbolName

public interface SortedMap<K, V> : MutableMap<K, V> {
    @KsSymbolName("__kk_sorted_map_comparator")
    public fun comparator(): Comparator<in K>?

    @KsSymbolName("__kk_sorted_map_first_key")
    public fun firstKey(): K

    @KsSymbolName("__kk_sorted_map_last_key")
    public fun lastKey(): K

    @KsSymbolName("__kk_sorted_map_head_map")
    public fun headMap(toKey: K): SortedMap<K, V>

    @KsSymbolName("__kk_sorted_map_tail_map")
    public fun tailMap(fromKey: K): SortedMap<K, V>

    @KsSymbolName("__kk_sorted_map_sub_map")
    public fun subMap(fromKey: K, toKey: K): SortedMap<K, V>
}
