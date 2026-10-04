package kotlinx.coroutines

import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

// `CoroutineId` context element from kotlinx-coroutines CoroutineId.kt.
// Debuggers and tracing use it to name a coroutine; the runtime context set is
// closed (resolveToCoroutineContext), so for now it is an ordinary
// `AbstractCoroutineContextElement` usable through `ctx[CoroutineId]`.
//
// The context key is a top-level object: a companion `object Key` cannot be
// referenced from the declaring class's own supertype-constructor argument
// list (the companion accessor does not resolve there). `CoroutineId.Key`
// stays public API through the companion member property, so
// `ctx[CoroutineId]` reads exactly like upstream.
internal object CoroutineIdKey : CoroutineContext.Key<CoroutineId>

@ExperimentalCoroutinesApi
public class CoroutineId(id: Long) : AbstractCoroutineContextElement(CoroutineIdKey) {

    public companion object {
        public val Key: CoroutineContext.Key<CoroutineId> = CoroutineIdKey
    }

    public val id: Long = id

    override fun toString(): String = "CoroutineId($id)"
}
