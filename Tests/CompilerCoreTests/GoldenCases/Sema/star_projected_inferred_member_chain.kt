package golden.sema

// KUU-3799: an inferred member property initialized through a covariant
// interface override must publish its substituted type before function
// bodies read it through a star-projected smart cast.
interface StarMapBuilder<K, V> { fun build(): Any }
interface StarMap<K, V> { fun builder(): StarMapBuilder<K, V> }
class ChainNode<K, V> {
    fun <K1, V1> equalsWith(that: ChainNode<K1, V1>, cmp: (V, V1) -> Boolean): Boolean = true
}
class ChainValue<V>(val value: V)

class StarHashMap<K, V>(val node: ChainNode<K, V>) : StarMap<K, V> {
    override fun builder(): StarHashMapBuilder<K, V> = StarHashMapBuilder(this)
    override fun equals(other: Any?): Boolean {
        if (other !is Map<*, *>) return false
        return when (other) {
            is StarOrderedMapBuilder<*, *> -> node.equalsWith(other.hashMapBuilder.node) { a, b -> a == b.value }
            is StarHashMapBuilder<*, *> -> node.equalsWith(other.node) { a, b -> a == b }
            else -> false
        }
    }
    override fun hashCode(): Int = 0
}

class StarHashMapBuilder<K, V>(map: StarHashMap<K, V>) : StarMapBuilder<K, V> {
    var builtMap: StarHashMap<K, V>? = map
        private set
    // A custom setter keeps the full declaration check on the normal pass,
    // but the initializer alone must still publish the property type early.
    var node = map.node
        set(value) {
            if (value !== field) {
                field = value
                builtMap = null
            }
        }
    override fun build(): Any = this
}

class StarOrderedMap<K, V>(val hashMap: StarHashMap<K, ChainValue<V>>)
class StarOrderedMapBuilder<K, V>(map: StarOrderedMap<K, V>) {
    val hashMapBuilder = map.hashMap.builder()
}
