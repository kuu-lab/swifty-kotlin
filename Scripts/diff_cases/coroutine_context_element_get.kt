// KUU-1405: `coroutineContext[Key]` element lookup and `withContext(element)`
// merging. The runtime context used to drop non-modeled elements and could
// not resolve several key companions, so `[Job]`/`[CoroutineName]` were null
// inside coroutines and `withContext(elem)` hid the element entirely.
import kotlinx.coroutines.*
import kotlin.coroutines.*

class TraceElement(val id: Int) : CoroutineContext.Element {
    companion object Key : CoroutineContext.Key<TraceElement>
    override val key: CoroutineContext.Key<*> get() = Key
}

// `Job by` delegates report Job.Key through the delegated `key`; once stored
// under Job.Key their `get`/`job` views resolve to the inner Job, like kotlinx.
class DelegatingJob : Job by Job()

@OptIn(ExperimentalStdlibApi::class)
fun main() = runBlocking {
    println(coroutineContext[Job] != null)
    println(coroutineContext.job != null)
    launch { println(coroutineContext[Job] != null) }.join()
    coroutineScope { println(coroutineContext[Job] != null) }
    supervisorScope { println(coroutineContext[Job] != null) }
    println(async { coroutineContext[Job] != null }.await())
    withContext(Job()) { println(coroutineContext[Job] != null) }
    withContext(CoroutineName("x")) {
        println(coroutineContext[CoroutineName]?.name)
    }
    val ctx = coroutineContext + CoroutineName("z")
    println(ctx[CoroutineName]?.name)

    // Dispatcher/interceptor keys resolve the same element.
    val dctx = Dispatchers.Default + CoroutineName("n")
    println(dctx[ContinuationInterceptor] != null)
    println(dctx[CoroutineDispatcher] != null)
    println(dctx.minusKey(ContinuationInterceptor)[ContinuationInterceptor] != null)
    println(dctx.minusKey(CoroutineDispatcher)[CoroutineDispatcher] != null)

    // CoroutineExceptionHandler has a Key companion like the other builtins.
    val handler = CoroutineExceptionHandler { _, _ -> }
    val hctx = coroutineContext + handler
    println(hctx[CoroutineExceptionHandler] === handler)
    println(hctx.minusKey(CoroutineExceptionHandler)[CoroutineExceptionHandler] != null)

    // Arbitrary source-defined elements survive composition and propagation.
    val elem = TraceElement(1)
    val tctx = coroutineContext + elem
    println(tctx[TraceElement]?.id)
    println((tctx + TraceElement(2))[TraceElement]?.id)
    println(tctx.minusKey(TraceElement)[TraceElement] != null)
    withContext(elem) {
        println(coroutineContext[TraceElement]?.id)
        println(coroutineContext[Job] != null)
    }
    launch(elem) { println(coroutineContext[TraceElement]?.id) }.join()
    println(coroutineContext[TraceElement] != null)
    println((Dispatchers.Default + TraceElement(3)).fold(0) { acc, _ -> acc + 1 })

    val dj = DelegatingJob()
    println(dj.key === Job.Key)
    val djctx = coroutineContext + dj
    println(djctx[Job] != null)
    println(djctx[Job] === dj)
    println(djctx.minusKey(Job)[Job] != null)
}
