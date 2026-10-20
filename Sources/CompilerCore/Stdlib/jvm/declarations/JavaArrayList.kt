package java.util
// JDK declaration only; implementation remains in the JDK.
class ArrayList<T>: kotlin.collections.MutableList<T> {
    override val size: Int get() = 0
    override fun isEmpty(): Boolean = false
    override fun contains(element: T): Boolean = false
    override fun iterator(): kotlin.collections.Iterator<T> = null!!
    override fun get(index: Int): T = null!!
    override fun set(index: Int, element: T): T = null!!
    override fun removeAt(index: Int): T = null!!
    override fun add(element: T): Boolean = false
    override fun remove(element: T): Boolean = false
    override fun clear() {}
}
