import kotlinx.coroutines.*
fun main() = runBlocking {
    withContext(CoroutineName("parent")) {
    val outerScope = this
    val outerJob = currentCoroutineContext().job
    coroutineScope {
        val scope = this
        val scopeJob = currentCoroutineContext().job
        println("scope name: ${currentCoroutineContext()[CoroutineName]?.name}")
        println("scope owns job: ${scopeJob !== outerJob}")
        launch(CoroutineName("child")) {
            println("outer name: ${outerScope.coroutineContext[CoroutineName]?.name}")
            println("outer job: ${outerScope.coroutineContext.job === outerJob}")
            println("captured scope name: ${scope.coroutineContext[CoroutineName]?.name}")
            println("captured scope job: ${scope.coroutineContext.job === scopeJob}")
        }
    }
    val reason = CancellationException("original scope reason")
    try {
        coroutineScope { currentCoroutineContext().job.cancel(reason) }
    } catch (failure: CancellationException) {
        println("scope cause identity: ${failure === reason}")
        println("scope cause message: ${failure.message}")
    }
    println("parent name: ${currentCoroutineContext()[CoroutineName]?.name}")
    println("parent active: ${outerJob.isActive}")
}
}
