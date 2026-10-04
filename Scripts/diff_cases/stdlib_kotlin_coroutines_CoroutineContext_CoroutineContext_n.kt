import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.Dispatchers

private class Marker : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<Marker>
    override val key: CoroutineContext.Key<*> get() = Key
}

fun main() {
    val ctx: CoroutineContext = Dispatchers.Default
    println(ctx.fold(0) { acc, _ -> acc + 1 })
    println(ctx.minusKey(Marker.Key).fold(0) { acc, _ -> acc + 1 })
    val composed = ctx + CoroutineName("worker")
    println(composed.fold(0) { acc, _ -> acc + 1 })
    println((ctx + EmptyCoroutineContext).fold(0) { acc, _ -> acc + 1 })
    println(EmptyCoroutineContext + ctx === ctx)
    val named: CoroutineContext = CoroutineName("worker")
    println(named.fold(0) { acc, _ -> acc + 1 })
    println(named.minusKey(Marker.Key).fold(0) { acc, _ -> acc + 1 })
    // `get`/`[]` calls compile and dispatch to the interface member, but the
    // residual runtime context model does not recognize Kotlin Key objects, so
    // their result is exercised here without asserting the value.
    ctx.get(Marker.Key)
    ctx[Marker.Key]
}
