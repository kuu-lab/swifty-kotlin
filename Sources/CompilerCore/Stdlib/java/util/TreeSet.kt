package java.util

import kotlin.collections.Collection
import kotlin.collections.MutableIterator
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_tree_set_init")
private external fun <E> __kkTreeSetInit(set: TreeSet<E>, comparator: Comparator<in E>?)

@KsSymbolName("kk_list_iterator")
private external fun <E> __kkTreeSetIterator(set: TreeSet<E>): MutableIterator<E>

@KsSymbolName("__kk_collection_size")
private external fun <E> __kkTreeSetSize(set: TreeSet<E>): Int

@KsSymbolName("__kk_set_contains")
private external fun <E> __kkTreeSetContains(set: TreeSet<E>, element: E): Boolean

@KsSymbolName("__kk_set_is_empty")
private external fun <E> __kkTreeSetIsEmpty(set: TreeSet<E>): Boolean

@KsSymbolName("__kk_collection_containsAll")
private external fun <E> __kkTreeSetContainsAll(
    set: TreeSet<E>,
    elements: Collection<@UnsafeVariance E>
): Boolean

public open class TreeSet<E> : NavigableSet<E> {
    public constructor() {
        __kkTreeSetInit(this, null)
    }

    public constructor(comparator: Comparator<in E>?) {
        __kkTreeSetInit(this, comparator)
    }

    public constructor(elements: Collection<E>) : this() { addAll(elements) }

    public constructor(sortedSet: SortedSet<E>) : this(sortedSet.comparator()) { addAll(sortedSet) }

    override val size: Int
        get() = __kkTreeSetSize(this)

    override fun contains(element: E): Boolean = __kkTreeSetContains(this, element)

    override fun isEmpty(): Boolean = __kkTreeSetIsEmpty(this)

    override fun iterator(): MutableIterator<E> = __kkTreeSetIterator(this)

    override fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean =
        __kkTreeSetContainsAll(this, elements)
}
