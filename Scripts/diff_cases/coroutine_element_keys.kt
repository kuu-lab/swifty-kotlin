import kotlin.coroutines.*
import kotlinx.coroutines.*

object CustomKey : CoroutineContext.Key<CustomElement>
class CustomElement : CoroutineContext.Element {
    override val key: CoroutineContext.Key<*> get() = CustomKey
}

fun keyOf(element: CoroutineContext.Element) = element.key

fun main() = runBlocking {
    val job = Job()
    println(job.key === Job.Key)
    println(keyOf(job) === Job.Key)
    val child = launch {}
    println(child.key === Job.Key)
    println(keyOf(child) === Job.Key)
    child.invokeOnCompletion { println("cb") }
    child.join()
    println("after")
    println(Dispatchers.Default.key === ContinuationInterceptor.Key)
    println(keyOf(Dispatchers.Default) === ContinuationInterceptor.Key)
    val name = CoroutineName("n")
    println(name.key === CoroutineName.Key)
    println(keyOf(name) === CoroutineName.Key)
    println(keyOf(CustomElement()) === CustomKey)
    val task = async { 7 }
    println(task.key === Job.Key)
    println(keyOf(task) === Job.Key)
    task.await()
    val completed = CompletableDeferred<Int>(7)
    println(completed.key === Job.Key)
    println(keyOf(completed) === Job.Key)
}
