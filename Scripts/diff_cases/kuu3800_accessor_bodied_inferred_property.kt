// KUU-3800: PersistentHashSet.containsAll's `elements is PersistentHashSetBuilder`
// smart-cast branch reads `elements.node`. The builder's `node` is an inferred
// member property that also declares a custom setter body, which kept its
// header-registered Any? placeholder while PersistentHashSet (declared
// earlier) was checked, so `node.containsAll(elements.node, 0)` failed the
// TrieNode<E> argument constraint with KSWIFTK-TYPE-0001. Mirrors the upstream
// kotlinx.collections.immutable shape at 9f961e4dd419dff58ffea164dd41ebba68acc8d6.

internal class TrieNode<E>(val id: E) {
    fun containsAll(otherNode: TrieNode<E>, shift: Int): Boolean = id == otherNode.id
}

internal class PersistentHashSet<E>(
    internal val node: TrieNode<E>,
    override val size: Int
) : AbstractSet<E>() {
    override fun containsAll(elements: Collection<E>): Boolean {
        if (elements is PersistentHashSet) {
            return node.containsAll(elements.node, 0)
        }
        if (elements is PersistentHashSetBuilder) {
            return node.containsAll(elements.node, 0)
        }
        return super.containsAll(elements)
    }

    override fun iterator(): Iterator<E> = listOf(node.id).iterator()
}

internal class PersistentHashSetBuilder<E>(set: PersistentHashSet<E>) : AbstractMutableSet<E>() {
    internal var node = set.node
        private set(value) { field = value }
    override var size = set.size
    override fun add(element: E): Boolean = false
    override fun iterator(): MutableIterator<E> = mutableListOf<E>().iterator()
}

fun main() {
    val set = PersistentHashSet(TrieNode("root"), 1)
    val builder = PersistentHashSetBuilder(set)
    println(set.containsAll(builder))
    println(set.containsAll(listOf("other")))
    println(builder.node.id)
}
