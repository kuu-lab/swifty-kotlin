package kotlin.collections

import kotlin.jvm.internal.markers.KMutableSet

public abstract class AbstractMutableSet<E> protected constructor() : java.util.AbstractSet<E>(), KMutableSet {
    abstract override val size: Int
    public abstract fun add(element: E): Boolean
}
