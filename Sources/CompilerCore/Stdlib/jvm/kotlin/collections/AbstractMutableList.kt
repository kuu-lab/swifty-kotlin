package kotlin.collections

import kotlin.jvm.internal.markers.KMutableList

public abstract class AbstractMutableList<E> protected constructor() : java.util.AbstractList<E>(), KMutableList {
    abstract override val size: Int
    public abstract fun set(index: Int, element: E): E
    public abstract fun add(index: Int, element: E)
    public abstract fun removeAt(index: Int): E

    @kotlin.jvm.JvmName("remove")
    public fun removeIndex(index: Int): E = removeAt(index)
}
