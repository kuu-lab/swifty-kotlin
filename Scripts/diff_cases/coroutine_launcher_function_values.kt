import kotlinx.coroutines.*
import kotlin.time.Duration.Companion.seconds

fun CoroutineScope.scopeValue(): Int = 9

fun main() {
    val root: suspend CoroutineScope.() -> Int = { scopeValue() }
    println(runBlocking(block = root))
    runBlocking {
        var side = 0
        val f: suspend CoroutineScope.() -> Unit = {
            delay(1)
            side = 5
        }
        launch(block = f).join()
        println(side)
        launch(Dispatchers.Default, block = f).join()
        println(side)
        launch(start = CoroutineStart.LAZY, block = f).join()
        println(side)
        val scope: CoroutineScope = this
        scope.launch(block = f).join()
        println(side)

        val bonus = 7
        val g: suspend CoroutineScope.() -> Int = {
            delay(1)
            scopeValue() + bonus
        }
        val result: Int = async(block = g).await()
        println(result)
        println(async(start = CoroutineStart.LAZY, block = g).await())
        val switched: Int = withContext(Dispatchers.Default, block = g)
        println(switched)
        val timed: Int = withTimeout(1000L, block = g)
        println(timed)
        val nullable: Int? = withTimeoutOrNull(1000L, block = g)
        println(nullable)

        val zero: suspend CoroutineScope.() -> String = { "zero" }
        println(async(block = zero).await())
        val nullValue: suspend CoroutineScope.() -> Int? = { null }
        println(withContext(Dispatchers.Default, block = nullValue))
        val task: Deferred<Int> = async(block = g)
        println(task.await())
        val nullableTask: Deferred<Int?> = async(block = nullValue)
        println(nullableTask.await())
        val literalTask: Deferred<Int> = async { 11 }
        println(literalTask.await())
        val nullableLiteralTask: Deferred<Int?> = async { null as Int? }
        println(nullableLiteralTask.await())
        println(withTimeout(1000, block = g))
        println(withTimeout(1.seconds, block = g))
        println(withTimeoutOrNull(1000, block = nullValue))
        println(withTimeoutOrNull(1.seconds, block = nullValue))
        println(withTimeout(1000, block = zero))
        println(withTimeout(1000) { scopeValue() + bonus })
        println(withTimeoutOrNull(1000) { scopeValue() + bonus })
    }
}
