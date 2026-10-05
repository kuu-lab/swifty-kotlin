package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName

// Runtime-owned name handles cannot store AbstractCoroutineContextElement's
// Kotlin fields. Bridge the Element operations and properties instead.
public class CoroutineName @KsSymbolName("kk_coroutine_name_create") constructor(name: String) : CoroutineContext.Element {
    public companion object Key : CoroutineContext.Key<CoroutineName>

    @KsSymbolName("kk_coroutine_name_get")
    public val name: String

    @KsSymbolName("kk_coroutine_name_key_get")
    public override val key: CoroutineContext.Key<*>

    @KsSymbolName("kk_context_get")
    public override operator fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E?

    @KsSymbolName("kk_context_fold")
    public override fun <R> fold(initial: R, operation: (R, CoroutineContext.Element) -> R): R

    @KsSymbolName("kk_context_minusKey")
    public override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext

    public override fun toString(): String = "CoroutineName($name)"
}
