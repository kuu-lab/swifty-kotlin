import kotlinx.coroutines.*
import java.util.concurrent.Executor

@OptIn(ExperimentalCoroutinesApi::class, DelicateCoroutinesApi::class, ObsoleteCoroutinesApi::class)
fun main() {
    val executor = Executor { command -> command.run() }
    runBlocking {
        println(withContext(Dispatchers.Default) { 40 })
        println(withContext(Dispatchers.IO.limitedParallelism(2)) { 41 })
        println(withContext(Dispatchers.Unconfined) { 42 })
        println(withContext(executor.asCoroutineDispatcher()) { 43 })
    }
    for (count in listOf(0, -1)) {
        try { Dispatchers.Default.limitedParallelism(count) }
        catch (e: IllegalArgumentException) { println("parallelism rejected") }
        try { newFixedThreadPoolContext(count, "invalid") }
        catch (e: IllegalArgumentException) { println("threads rejected") }
    }
}
