// KUU-3799: nested member reads through a star-projected smart-cast receiver
// (`other.hashMapBuilder.node`, `other.node`) where the members' types are
// inferred — one through a covariant `builder()` override chain and one
// through a `var` with a custom setter. `equalsWith`-style generic member
// calls must infer K1/V1 from the captured argument types so `b.value`
// resolves.
interface IBuilder<K, V> { fun build(): Any }
interface IMap<K, V> { fun builder(): IBuilder<K, V> }
class TrieNode<K, V>(val key: K) {
    fun <K1, V1> equalsWith(that: TrieNode<K1, V1>, cmp: (V, V1) -> Boolean): Boolean = true
}
class LinkedValue<V>(val value: V)
abstract class AbsMap<K, V> : Map<K, V> {
    override val size: Int get() = 0
    override val keys: Set<K> get() = emptySet()
    override val values: Collection<V> get() = emptyList()
    override val entries: Set<Map.Entry<K, V>> get() = emptySet()
    override fun containsKey(key: K): Boolean = false
    override fun containsValue(value: V): Boolean = false
    override fun get(key: K): V? = null
    override fun isEmpty(): Boolean = true
}
class PersistentHashMap<K, V>(val node: TrieNode<K, V>) : AbsMap<K, V>(), IMap<K, V> {
    override fun builder(): PersistentHashMapBuilder<K, V> = PersistentHashMapBuilder(this)
    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is Map<*, *>) return false
        return when (other) {
            is PersistentOrderedMapBuilder<*, *> -> node.equalsWith(other.hashMapBuilder.node) { a, b -> a == b.value }
            is PersistentHashMapBuilder<*, *> -> node.equalsWith(other.node) { a, b -> a == b }
            else -> false
        }
    }
    override fun hashCode(): Int = 0
}
class PersistentHashMapBuilder<K, V>(map: PersistentHashMap<K, V>) : AbsMap<K, V>(), IBuilder<K, V> {
    var builtMap: PersistentHashMap<K, V>? = map
        private set
    var node = map.node
        set(value) {
            if (value !== field) {
                field = value
                builtMap = null
            }
        }
    override fun build(): Any = this
}
class PersistentOrderedMap<K, V>(val hashMap: PersistentHashMap<K, LinkedValue<V>>)
class PersistentOrderedMapBuilder<K, V>(map: PersistentOrderedMap<K, V>) : AbsMap<K, V>() {
    val hashMapBuilder = map.hashMap.builder()
}
fun main() {
    val m = PersistentHashMap<String, Int>(TrieNode<String, Int>("k"))
    val om = PersistentOrderedMapBuilder<String, Int>(
        PersistentOrderedMap<String, Int>(
            PersistentHashMap<String, LinkedValue<Int>>(TrieNode<String, LinkedValue<Int>>("k"))
        )
    )
    val b = PersistentHashMapBuilder<String, Int>(m)
    println(m.equals(om))
    println(m.equals(b))
}
