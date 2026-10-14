// KUU-2046: minimal consumers of the annotated calls/blocks in upstream
// Kotlin/kotlinx.collections.immutable at 9f961e4dd419dff58ffea164dd41ebba68acc8d6.
// PersistentHashMap.kt: putting/removing expression operands.
// immutableSet/TrieNode.kt: mutableAddAll's annotated generic-cast branch.
interface PersistentMap<K, V> {
    fun putting(key: K, value: V): PersistentMap<K, V>
    fun removing(key: K): PersistentMap<K, V>
}

class PersistentHashMap<K, V>(val size: Int) : PersistentMap<K, V> {
    @Deprecated("Use putting() instead")
    fun put(key: K, value: @UnsafeVariance V): PersistentHashMap<K, V> = PersistentHashMap(size + 1)
    @Deprecated("Use removing() instead")
    fun remove(key: K): PersistentHashMap<K, V> = PersistentHashMap(size - 1)
    override fun putting(key: K, value: V): PersistentHashMap<K, V> =
        @Suppress("DEPRECATION") put(key, value)
    override fun removing(key: K): PersistentHashMap<K, V> = @Suppress("DEPRECATION") remove(key)
}

class DeltaCounter(var count: Int)
class PersistentHashSetBuilder<E>(val size: Int)
const val LOG_MAX_BRANCHING_FACTOR: Int = 5

class TrieNode<E>(val count: Int) {
    fun mutableAddAll(
        otherNode: TrieNode<E>, shift: Int,
        intersectionSizeRef: DeltaCounter, mutator: PersistentHashSetBuilder<*>
    ): TrieNode<E> {
        intersectionSizeRef.count += shift + mutator.size
        return TrieNode(count + otherNode.count)
    }
}

fun <E> merge(
    thisCell: Any, otherNodeCell: Any, shift: Int,
    intersectionSizeRef: DeltaCounter, mutator: PersistentHashSetBuilder<*>
): TrieNode<E> {
    val thisIsNode = thisCell is TrieNode<*>
    val otherIsNode = otherNodeCell is TrieNode<*>
    return when {
        thisIsNode && otherIsNode -> @Suppress("UNCHECKED_CAST") {
            thisCell as TrieNode<E>
            otherNodeCell as TrieNode<E>
            thisCell.mutableAddAll(
                otherNodeCell, shift + LOG_MAX_BRANCHING_FACTOR,
                intersectionSizeRef, mutator
            )
        }
        else -> TrieNode<E>(9)
    }
}

fun main() {
    val map = PersistentHashMap<String, Int>(0)
    println(map.putting("key", 7).size)
    println(map.removing("key").size)
    val counter = DeltaCounter(0)
    val mutator = PersistentHashSetBuilder<Int>(2)
    println(merge<Int>(TrieNode<Int>(3), TrieNode<Int>(4), 0, counter, mutator).count)
    println(merge<Int>("key", "other", 0, counter, mutator).count)
    println(counter.count)
}
