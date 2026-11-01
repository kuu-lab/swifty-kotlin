package java.util.concurrent

import java.util.SortedSet
import java.util.TreeSet
import kotlin.internal.KsSymbolName

// KUU-4118: java.util.concurrent.ConcurrentSkipListSet — a NavigableSet over
// the same sorted backing box TreeSet uses; single-threaded execution makes
// the JVM skip-list's lock-free concurrency unobservable, so inheriting
// TreeSet is the delegation the ticket suggests. Construction goes through
// the TreeSet init-attach path (`__kk_tree_set_init`), which keeps
// MutableSet / SortedSet / NavigableSet members dispatching to the sorted
// runtime bridges on the subclass instance.
//
// JVM parity notes:
//  - The JVM ConcurrentSkipListSet is null-free: add/contains/remove and the
//    bulk-add constructors throw NullPointerException on null elements.
//    Bundled TreeSet does not guard, so the checks live here. The guards are
//    only reachable through ConcurrentSkipListSet-typed receivers: calls
//    through kotlin.collections interface receivers lower straight to the
//    `__kk_mutable_set_*` / `__kk_mutable_collection_*` bridges, the same
//    bypass the sorted interfaces document in SortedSet.kt.
//  - `is java.util.TreeSet<*>` answers true on these instances because the
//    class literally extends TreeSet; on the JVM it is false. The Kotlin
//    surface cannot observe the difference — `is TreeSet` against the
//    static type is a compile error on the JVM.
//  - toString/equals/hashCode need Kotlin bodies (AbstractCollection /
//    AbstractSet shapes): source-allocated instances cannot lean on the
//    box-level Any fallbacks the way RuntimeSetBox handles do.

@KsSymbolName("__kk_mutable_set_add")
private external fun <E> __kkCslsAdd(set: ConcurrentSkipListSet<E>, element: E): Boolean

@KsSymbolName("__kk_mutable_set_remove")
private external fun <E> __kkCslsRemove(set: ConcurrentSkipListSet<E>, element: E): Boolean

@KsSymbolName("__kk_set_contains")
private external fun <E> __kkCslsContains(set: ConcurrentSkipListSet<E>, element: E): Boolean

public open class ConcurrentSkipListSet<E> : TreeSet<E> {
    public constructor() : super()

    public constructor(comparator: Comparator<in E>?) : super(comparator)

    public constructor(elements: Collection<E>) : super() {
        // TreeSet's own `addAll(elements)` would lower to the external
        // `__kk_mutable_collection_addAll_throwing` bridge and skip the
        // null guard below, so the copy runs through this class's addAll.
        addAll(elements)
    }

    public constructor(sortedSet: SortedSet<E>) : super(sortedSet.comparator()) {
        addAll(sortedSet)
    }

    override fun add(element: E): Boolean {
        if (element == null) throw NullPointerException()
        return __kkCslsAdd(this, element)
    }

    override fun addAll(elements: Collection<E>): Boolean {
        // Iterating member-wise matches the JVM AbstractCollection path: a
        // null element throws partway through and keeps the elements already
        // inserted.
        var changed = false
        for (element in elements) {
            if (add(element)) changed = true
        }
        return changed
    }

    override fun contains(element: E): Boolean {
        if (element == null) throw NullPointerException()
        return __kkCslsContains(this, element)
    }

    override fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean {
        for (element in elements) {
            if (!contains(element)) return false
        }
        return true
    }

    override fun remove(element: E): Boolean {
        if (element == null) throw NullPointerException()
        return __kkCslsRemove(this, element)
    }

    /** JVM `clone()`: a fresh set carrying the same comparator and elements. */
    public fun clone(): ConcurrentSkipListSet<E> {
        val copy = ConcurrentSkipListSet<E>(comparator())
        copy.addAll(this)
        return copy
    }

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is Set<*>) return false
        var otherSize = 0
        for (element in other) {
            otherSize += 1
            var found = false
            for (ownElement in this) {
                if (ownElement == element) {
                    found = true
                    break
                }
            }
            if (!found) return false
        }
        return size == otherSize
    }

    override fun hashCode(): Int {
        var hashCode = 0
        for (element in this) {
            hashCode += element?.hashCode() ?: 0
        }
        return hashCode
    }

    override fun toString(): String = joinToString(", ", "[", "]") { element ->
        if (element === this) "(this Collection)" else element.toString()
    }
}
