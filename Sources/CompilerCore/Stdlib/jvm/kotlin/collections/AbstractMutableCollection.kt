package kotlin.collections

import kotlin.jvm.internal.markers.KMutableCollection

public abstract class AbstractMutableCollection<E> protected constructor() :
    java.util.AbstractCollection<E>(), KMutableCollection {
    abstract override val size: Int
    public abstract fun add(element: E): Boolean
}
