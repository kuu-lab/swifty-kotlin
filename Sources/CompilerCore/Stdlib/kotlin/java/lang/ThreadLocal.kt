package java.lang

import java.util.function.Supplier
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_thread_local_new")
private external fun __threadLocalNew(): Long

@KsSymbolName("__kk_thread_local_has_value")
private external fun __threadLocalHasValue(handle: Long): kotlin.Boolean

@KsSymbolName("__kk_thread_local_value")
private external fun __threadLocalValue(handle: Long): Any?

@KsSymbolName("__kk_thread_local_store")
private external fun __threadLocalStore(handle: Long, value: Any?): Unit

@KsSymbolName("__kk_thread_local_remove")
private external fun __threadLocalRemove(handle: Long): Unit

public open class ThreadLocal<T> {
    private val handle: Long = __threadLocalNew()

    // Sema exposes these Java method results as T! in both stdlib modes.
    protected open fun initialValue(): T? = null

    public open fun get(): T? {
        if (!__threadLocalHasValue(handle)) {
            __threadLocalStore(handle, initialValue())
        }
        return __threadLocalValue(handle) as T?
    }

    public open fun set(value: T): Unit = __threadLocalStore(handle, value)

    public open fun remove(): Unit = __threadLocalRemove(handle)

    public companion object {
        @JvmStatic
        public fun <S> withInitial(supplier: Supplier<out S>): ThreadLocal<S> {
            return object : ThreadLocal<S>() {
                override fun initialValue(): S? = supplier.get()
            }
        }
    }

    @PublishedApi
    internal fun __storeValue(value: T?): Unit = __threadLocalStore(handle, value)
}
