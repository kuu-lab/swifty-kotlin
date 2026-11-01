package kotlin.collections

public fun <K, V> linkedMapOf(vararg pairs: Pair<K, V>): java.util.LinkedHashMap<K, V> = null!!

public fun <K, V> sortedMapOf(vararg pairs: Pair<K, V>): java.util.SortedMap<K, V> = null!!
public fun <K, V> sortedMapOf(
    comparator: kotlin.Comparator<in K>,
    vararg pairs: Pair<K, V>
): java.util.SortedMap<K, V> = null!!

public fun <K : Comparable<K>, V> Map<out K, V>.toSortedMap(): java.util.SortedMap<K, V> = null!!
public fun <K, V> Map<out K, V>.toSortedMap(comparator: kotlin.Comparator<in K>): java.util.SortedMap<K, V> = null!!

public fun <K, V> Map<out K, V>.toMutableMap(): MutableMap<K, V> = null!!
public fun <K, V> Map<out K, V>.toMap(): Map<K, V> = null!!
public fun <K, V> Array<out Pair<K, V>>.toMap(): Map<K, V> = null!!
