/*
 * KUU-1361: JVM java.util.TreeSet parity for the bundled stdlib.
 */

package java.util

import kotlin.collections.Collection
import kotlin.collections.MutableIterator
import kotlin.internal.KsSymbolName

// Construction is lowered to the runtime sorted-set entry points
// (`__kk_tree_set_new` for the empty/comparator forms,
// `__kk_tree_set_new_collection`/`__kk_tree_set_new_sorted_set` for the copy
// forms) by `CollectionLiteralLoweringPass`. Boxes carry
// `treeSetRuntimeTypeID`, so constructed instances answer
// `is java.util.TreeSet<*>` / `is java.util.SortedSet<*>` /
// `is java.util.NavigableSet<*>` / `is MutableSet<*>`.
//
// The `init` block additionally attaches a sorted backing `RuntimeSetBox` to
// source-allocated instances (including user subclasses) so `MutableSet`
// member calls operate on real storage — the LinkedHashSet.kt precedent.
// The comparator does not survive that path for subclasses; see
// docs/stdlib-pipeline.md.

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

/**
 * A sorted set backed by a runtime box — `java.util.TreeSet`.
 */
public open class TreeSet<E> : NavigableSet<E> {
    public constructor() {
        __kkTreeSetInit(this, null)
    }

    public constructor(comparator: Comparator<in E>?) {
        __kkTreeSetInit(this, null)
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
