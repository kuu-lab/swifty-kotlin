@file:kotlin.jvm.JvmName("LazyKt")
package kotlin
import kotlin.jvm.internal.*
private object Uninitialized
private class LockedLazy<T>(private var initializer: (() -> T)?, private val lock: Any): Lazy<T> {
    private val state: Any = __jvmAtomicReference(Uninitialized)
    override val value: T get() {
        val previous = __jvmAtomicGet(state)
        if (previous !== Uninitialized) return previous as T
        __jvmMonitorEnter(lock)
        try {
            val current = __jvmAtomicGet(state)
            if (current !== Uninitialized) return current as T
            val computed = initializer!!()
            __jvmAtomicSet(state, computed)
            initializer = null
            return computed
        } finally { __jvmMonitorExit(lock) }
    }
    override fun isInitialized(): Boolean = __jvmAtomicGet(state) !== Uninitialized
    override fun toString(): String = if (isInitialized()) "${__jvmAtomicGet(state)}" else "Lazy value not initialized yet."
}
private class PublicationLazy<T>(private var initializer: (() -> T)?): Lazy<T> {
    private val state: Any = __jvmAtomicReference(Uninitialized)
    override val value: T get() {
        val current = __jvmAtomicGet(state)
        if (current !== Uninitialized) return current as T
        val factory = initializer
        if (factory != null) {
            val computed = factory()
            if (__jvmAtomicCAS(state, Uninitialized, computed)) { initializer = null; return computed }
        }
        return __jvmAtomicGet(state) as T
    }
    override fun isInitialized(): Boolean = __jvmAtomicGet(state) !== Uninitialized
    override fun toString(): String = if (isInitialized()) "${__jvmAtomicGet(state)}" else "Lazy value not initialized yet."
}
private class UnsafeLazy<T>(private var initializer: (() -> T)?): Lazy<T> {
    private var stored: Any? = Uninitialized
    override val value: T get() {
        if (stored === Uninitialized) { stored = initializer!!(); initializer = null }
        return stored as T
    }
    override fun isInitialized(): Boolean = stored !== Uninitialized
    override fun toString(): String = if (isInitialized()) "$stored" else "Lazy value not initialized yet."
}
fun <T> lazy(initializer: () -> T): Lazy<T> = LockedLazy(initializer, __jvmAtomicReference(null))
fun <T> lazy(mode: LazyThreadSafetyMode, initializer: () -> T): Lazy<T> = when (mode) {
    LazyThreadSafetyMode.NONE -> UnsafeLazy(initializer)
    LazyThreadSafetyMode.PUBLICATION -> PublicationLazy(initializer)
    else -> LockedLazy(initializer, __jvmAtomicReference(null))
}
fun <T> lazy(lock: Any?, initializer: () -> T): Lazy<T> = LockedLazy(initializer, lock ?: __jvmAtomicReference(null))
operator fun <T> Lazy<T>.getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): T = value
