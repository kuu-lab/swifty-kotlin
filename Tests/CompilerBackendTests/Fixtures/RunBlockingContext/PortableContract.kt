import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.*

fun main() {
    check(runBlocking { 3 } == 3)
    check(runBlocking(context = EmptyCoroutineContext) { 4 } == 4)
    println("default=3|explicit-empty=4")

    val parent = Job()
    var child: Job? = null
    val value: String = runBlocking(parent + CoroutineName("parent")) {
        child = currentCoroutineContext()[Job]
        check(child !== parent && child != null)
        check(parent.children.any { it === child })
        check(currentCoroutineContext()[CoroutineName]?.name == "parent")
        delay(1)
        check(currentCoroutineContext()[CoroutineName]?.name == "parent")
        "name-ok"
    }
    check(parent.isActive && child?.isCompleted == true)
    check(!parent.children.iterator().hasNext())
    println("$value|fresh-child|parent-active|child-completed-detached")

    val captured = "captured"
    val block: suspend CoroutineScope.() -> String = {
        delay(1)
        captured + ":" + currentCoroutineContext()[CoroutineName]?.name
    }
    check(runBlocking(context = CoroutineName("value"), block = block) == "captured:value")
    println("function-value=captured:value")

    runBlocking(CoroutineName("outer")) {
        val outerJob = currentCoroutineContext()[Job]
        val interceptor = currentCoroutineContext()[ContinuationInterceptor]
        runBlocking {
            check(currentCoroutineContext()[CoroutineName] == null)
            check(currentCoroutineContext()[Job] !== outerJob)
            check(currentCoroutineContext()[ContinuationInterceptor] === interceptor)
            yield()
        }
        check(currentCoroutineContext()[CoroutineName]?.name == "outer")
        check(currentCoroutineContext()[Job] === outerJob)
        runBlocking(currentCoroutineContext() + CoroutineName("inner")) {
            check(currentCoroutineContext()[CoroutineName]?.name == "inner")
            check(currentCoroutineContext()[Job] !== outerJob)
            check(currentCoroutineContext()[ContinuationInterceptor] === interceptor)
            yield()
        }
        check(currentCoroutineContext()[CoroutineName]?.name == "outer")
    }
    println("nested=default-detached|explicit-inherits|loop-reused|outer-restored")

    val cancelled = Job()
    cancelled.cancel()
    var entered = false
    var rejected = false
    try {
        runBlocking(cancelled) { entered = true }
    } catch (failure: CancellationException) {
        rejected = true
    }
    check(rejected && !entered)
    println("pre-cancelled-parent=CancellationException|body-not-entered")

    val cancelledDuringBody = Job()
    var finalized = false
    rejected = false
    try {
        runBlocking(cancelledDuringBody) {
            try {
                cancelledDuringBody.cancel()
                yield()
            } finally {
                finalized = true
            }
        }
    } catch (failure: CancellationException) {
        rejected = true
    }
    check(rejected && finalized && cancelledDuringBody.isCancelled)
    println("parent-cancel=CancellationException|finally-ran")

    val failureParent = Job()
    var handlerCalls = 0
    val handler = CoroutineExceptionHandler { _, _ -> handlerCalls += 1 }
    var bodyThrown = false
    try {
        runBlocking(failureParent + handler) { throw IllegalStateException("body") }
    } catch (failure: IllegalStateException) {
        check(failure.message == "body")
        bodyThrown = true
    }
    check(bodyThrown && handlerCalls == 0 && failureParent.isActive)
    var childThrown = false
    try {
        runBlocking(failureParent + handler) {
            launch { throw IllegalArgumentException("child") }
            delay(100)
        }
    } catch (failure: IllegalArgumentException) {
        check(failure.message == "child")
        childThrown = true
    }
    check(childThrown && handlerCalls == 0 && failureParent.isActive)
    println("failures=body-child-rethrown|handler-not-called|parent-active")
}
