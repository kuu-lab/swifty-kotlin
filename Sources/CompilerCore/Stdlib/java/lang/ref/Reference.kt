@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package java.lang.ref

import kotlin.native.ref.WeakReference as NativeWeakReference

/** Base type for references exposed by java.lang.ref. */
public open class Reference<T : Any> internal constructor(referent: T) {
    private val weakReferent = NativeWeakReference(referent)
    private var cleared = false

    public open fun get(): T? = if (cleared) null else weakReferent.value

    public open fun clear() {
        cleared = true
        weakReferent.clear()
    }

    public open fun enqueue(): Boolean = false

    public open val isEnqueued: Boolean
        get() = false
}

/** A non-owning reference that becomes null after its referent is collected. */
public class WeakReference<T : Any> : Reference<T> {
    public constructor(referent: T) : super(referent)
}

/** A reference that keeps its referent until explicitly cleared. */
public class SoftReference<T : Any> : Reference<T> {
    private var retainedReferent: T? = null

    public constructor(referent: T) : super(referent) {
        retainedReferent = referent
    }

    override fun get(): T? = retainedReferent

    override fun clear() {
        retainedReferent = null
        super.clear()
    }
}
