package kotlinx.coroutines

import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

// The runtime context set is closed (resolveToCoroutineContext), so for now it
// is an ordinary `AbstractCoroutineContextElement` usable through
// `ctx[CoroutineId]`.
@ExperimentalCoroutinesApi
public class CoroutineId(id: Long) : AbstractCoroutineContextElement(CoroutineId.Key) {
    public companion object Key : CoroutineContext.Key<CoroutineId>

    public val id: Long = id

    override fun toString(): String = "CoroutineId($id)"
}
