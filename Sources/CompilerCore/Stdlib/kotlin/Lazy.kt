package kotlin

import kotlin.internal.KsSymbolName

public interface Lazy<out T>

@KsSymbolName("kk_lazy_get_value")
private external fun <T> Lazy<T>.__kk_lazy_get_value(): T

@KsSymbolName("kk_lazy_is_initialized")
private external fun <T> Lazy<T>.__kk_lazy_is_initialized(): Boolean

public fun <T> Lazy<T>.value(): T =
    __kk_lazy_get_value()

public fun <T> Lazy<T>.isInitialized(): Boolean =
    __kk_lazy_is_initialized()
