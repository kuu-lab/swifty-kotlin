package kotlin

import kotlin.internal.KsSymbolName

public interface Lazy<out T> {
    public val value: T
    public fun isInitialized(): Boolean
}

// KSP-781: top-level lazy factories are bundled Kotlin source.
// The delegate lowering path still uses its separate runtime-backed handle;
// this implementation covers ordinary Lazy values returned by these factories.

@KsSymbolName("__kk_lazy_sync_lock")
private external fun __lazySyncLock(lock: Any): Unit

@KsSymbolName("__kk_lazy_sync_unlock")
private external fun __lazySyncUnlock(lock: Any): Unit

internal class LazyImpl<T>(
    private val initializer: () -> T,
    private val mode: LazyThreadSafetyMode,
    private val synchronizationLock: Any?,
    initialValue: Any?,
    initialComputed: Boolean
) : Lazy<T> {
    private var cached: Any? = initialValue
    private var computed: Boolean = initialComputed

    @Suppress("UNCHECKED_CAST")
    private fun computeValue(): T {
        if (mode == LazyThreadSafetyMode.PUBLICATION) {
            return computePublicationValue()
        }
        if (!computed) {
            if (mode == LazyThreadSafetyMode.SYNCHRONIZED) {
                __lazySyncLock(synchronizationLock ?: this)
                try {
                    if (!computed) {
                        cached = initializer()
                        computed = true
                    }
                } finally {
                    __lazySyncUnlock(synchronizationLock ?: this)
                }
            } else {
                if (!computed) {
                    cached = initializer()
                    computed = true
                }
            }
        }
        return cached as T
    }

    @Suppress("UNCHECKED_CAST")
    private fun computePublicationValue(): T {
        // PUBLICATION may run the initializer more than once, but only the
        // first completed value is published. Synchronize both the fast-path
        // read and the commit so the published value is never overwritten.
        var published: Any? = null
        var wasInitialized = false
        synchronized(this) {
            if (computed) {
                published = cached
                wasInitialized = true
            }
        }
        if (wasInitialized) {
            return published as T
        }

        val candidate = initializer()
        synchronized(this) {
            if (!computed) {
                cached = candidate
                computed = true
            }
            published = cached
        }
        return published as T
    }

    override val value: T
        get() = computeValue()

    override fun isInitialized(): Boolean {
        if (mode != LazyThreadSafetyMode.PUBLICATION) {
            return computed
        }
        var initialized = false
        synchronized(this) {
            initialized = computed
        }
        return initialized
    }
}

public fun <T> lazy(initializer: () -> T): Lazy<T> =
    LazyImpl(initializer, LazyThreadSafetyMode.SYNCHRONIZED, null, null, false)

public fun <T> lazy(lock: Any?, initializer: () -> T): Lazy<T> =
    LazyImpl(initializer, LazyThreadSafetyMode.SYNCHRONIZED, lock, null, false)

public fun <T> lazy(
    mode: LazyThreadSafetyMode,
    initializer: () -> T
): Lazy<T> = LazyImpl(initializer, mode, null, null, false)

public fun <T> lazyOf(value: T): Lazy<T> = LazyImpl(
    { throw IllegalStateException("unreachable: lazyOf value is pre-seeded") },
    LazyThreadSafetyMode.NONE,
    null,
    value,
    true
)
