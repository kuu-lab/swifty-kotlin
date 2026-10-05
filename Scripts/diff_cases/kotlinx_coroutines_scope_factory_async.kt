import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.*

fun checkScope(scope: CoroutineScope) {
    scope.ensureActive()
    println(scope.isActive)
    println(scope.coroutineContext.isActive)
}

class UserState(val isActive: Boolean)

fun main() = runBlocking {
    println(UserState(false).isActive)
    val parent = Job()
    val child = Job(parent)
    println(child.parent === parent)
    println(parent.children.toList().size)
    println(child.complete())
    println(child.isCompleted)
    val scope = CoroutineScope(EmptyCoroutineContext)
    println(scope.async { 42 }.await())
    val custom = object : CoroutineScope { override val coroutineContext = Job() }
    println(custom.async { 43 }.await())
    scope.cancel()
    try { scope.async { 99 }.await() } catch (e: CancellationException) { println("cancelled") }
    println(custom.isActive)
    custom.cancel()
    supervisorScope {
        checkScope(this)
        ensureActive()
        println(this.isActive)
        println(this.coroutineContext.isActive)
        println(isActive)
        launch { println(coroutineContext.isActive); println(isActive) }.join()
        println(async { 44 }.await())
    }
    try {
        supervisorScope {
            cancel()
            println(isActive)
            ensureActive()
        }
    } catch (e: CancellationException) { println("runtime cancelled") }
}
