// MutableMap.keys/.values must be typed MutableSet<K>/MutableCollection<V>
// (write-through to the map) instead of the read-only Set<K>/Collection<V>
// inherited from Map, so remove()/clear()/retainAll() type-check and mutate
// the map. entries already had the right type; this covers keys/values.
fun main() {
    val m = mutableMapOf(1 to "a", 2 to "b")
    val ks = m.keys; ks.remove(1); println(m)
    m.keys.remove(2); println(m)
    val m2 = mutableMapOf(1 to "a", 2 to "b"); m2.values.remove("a"); println(m2)
    val m3 = mutableMapOf(1 to "a", 2 to "b"); m3.entries.retainAll { it.key != 1 }; println(m3)
    val m4 = mutableMapOf(1 to "a"); m4.keys.clear(); println(m4)
}
