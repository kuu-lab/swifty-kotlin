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
                // PUBLICATION and NONE are intentionally lock-free here. The
                // single-threaded semantics match the Kotlin standard library;
                // the runtime-backed delegate path retains its own mode handling.
                if (!computed) {
                    cached = initializer()
                    computed = true
                }
            }
        }
        return cached as T
    }

    override val value: T
        get() = computeValue()

    override fun isInitialized(): Boolean = computed
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
