// KUU-1395: runBlocking installs its event loop as the ContinuationInterceptor
// element (kotlinx's BlockingEventLoop), so coroutineContext[ContinuationInterceptor]
// resolves a CoroutineDispatcher — alongside the coroutine's Job — and fold /
// minusKey / override-merge / child inheritance all observe it.
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainCoroutineDispatcher
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

// `coroutineContext[CoroutineDispatcher]` uses the ExperimentalStdlibApi key.
@OptIn(ExperimentalStdlibApi::class)
fun main() = runBlocking {
    val interceptor = coroutineContext[ContinuationInterceptor]
    println(interceptor != null)
    println(interceptor is CoroutineDispatcher)
    println(interceptor is CoroutineContext.Element)
    println(interceptor is ContinuationInterceptor)
    println(interceptor is MainCoroutineDispatcher == false)
    println((interceptor as? CoroutineContext.Element)?.key === ContinuationInterceptor)
    println(coroutineContext[CoroutineDispatcher] != null)
    println(coroutineContext[Job] != null)
    println(coroutineContext[ContinuationInterceptor] === interceptor)

    var sawInterceptor = false
    var sawJob = false
    coroutineContext.fold(Unit) { _, element ->
        if (element is ContinuationInterceptor) sawInterceptor = true
        if (element is Job) sawJob = true
    }
    println(sawInterceptor)
    println(sawJob)

    val stripped = coroutineContext.minusKey(ContinuationInterceptor)
    println(stripped[ContinuationInterceptor] == null)
    println(stripped[Job] != null)
    println(coroutineContext.minusKey(CoroutineDispatcher)[ContinuationInterceptor] == null)

    println(EmptyCoroutineContext[ContinuationInterceptor] == null)

    val job = launch {
        println(coroutineContext[ContinuationInterceptor] is CoroutineDispatcher)
        println(coroutineContext[Job] != null)
    }
    job.join()

    coroutineScope {
        println(coroutineContext[ContinuationInterceptor] is CoroutineDispatcher)
    }

    val named = coroutineContext + CoroutineName("x")
    println(named[ContinuationInterceptor] is CoroutineDispatcher)
    println(named[CoroutineName]?.name)

    // An explicit dispatcher wins over the inherited loop element.
    withContext(Dispatchers.Default) {
        println(coroutineContext[ContinuationInterceptor] === Dispatchers.Default)
        println(coroutineContext[CoroutineDispatcher] === Dispatchers.Default)
    }
    println(coroutineContext[ContinuationInterceptor] === interceptor)

    val scope = CoroutineScope(coroutineContext)
    println(scope.coroutineContext[ContinuationInterceptor] is CoroutineDispatcher)
}
