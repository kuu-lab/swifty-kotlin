fun <K, V> contracts(map: MutableMap<K, V>, from: Map<out K, V>, key: K, value: V): V? {
    val entries: MutableSet<MutableMap.MutableEntry<K, V>> = map.entries
    val keys: MutableSet<K> = map.keys
    val values: MutableCollection<V> = map.values
    val old: V? = map.put(key, value)
    map.putAll(from = from)
    val removed: V? = map.remove(key)
    map.clear()
    return old
}
