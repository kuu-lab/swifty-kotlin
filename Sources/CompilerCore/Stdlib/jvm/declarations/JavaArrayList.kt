package java.util
// JDK declaration only; implementation remains in the JDK.
class ArrayList<T>: kotlin.collections.MutableList<T> {
    override val size: Int get() = 0
    override fun isEmpty(): Boolean = false
    override fun contains(element: T): Boolean = false
    override fun containsAll(elements: kotlin.collections.Collection<out T>): Boolean = false
    override fun iterator(): kotlin.collections.Iterator<T> = null!!
    override fun get(index: Int): T = null!!
    override fun indexOf(element: T): Int = -1
    override fun lastIndexOf(element: T): Int = -1
    override fun listIterator(): kotlin.collections.MutableListIterator<T> = null!!
    override fun listIterator(index: Int): kotlin.collections.MutableListIterator<T> = null!!
    override fun subList(fromIndex: Int, toIndex: Int): kotlin.collections.MutableList<T> = null!!
    override fun set(index: Int, element: T): T = null!!
    override fun removeAt(index: Int): T = null!!
    override fun add(element: T): Boolean = false
    override fun add(index: Int, element: T) {}
    override fun addAll(elements: kotlin.collections.Collection<out T>): Boolean = false
    override fun addAll(index: Int, elements: kotlin.collections.Collection<out T>): Boolean = false
    override fun remove(element: T): Boolean = false
    override fun removeAll(elements: kotlin.collections.Collection<out T>): Boolean = false
    override fun retainAll(elements: kotlin.collections.Collection<out T>): Boolean = false
    override fun clear() {}
}
