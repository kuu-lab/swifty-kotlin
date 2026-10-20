package kotlin.collections
operator fun <K, V> Map<out K, V>.minus(key: K): Map<K, V> = null!!
operator fun <K, V> Map<out K, V>.minus(keys: Iterable<K>): Map<K, V> = null!!
operator fun <K, V> Map<out K, V>.plus(pair: Pair<K, V>): Map<K, V> = null!!
operator fun <K, V> Map<out K, V>.plus(map: Map<out K, V>): Map<K, V> = null!!
