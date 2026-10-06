package golden.sema

import kotlinx.coroutines.*
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService

fun defaultDispatcher(): CoroutineDispatcher = Dispatchers.Default
fun ioDispatcher(): CoroutineDispatcher = Dispatchers.IO
fun unconfinedDispatcher(): CoroutineDispatcher = Dispatchers.Unconfined
fun mainDispatcher(): CoroutineDispatcher = Dispatchers.Main.immediate
fun limitedDispatcher(dispatcher: CoroutineDispatcher): CoroutineDispatcher = dispatcher.limitedParallelism(2)
fun singleDispatcher(): CoroutineDispatcher = newSingleThreadContext("single")
fun fixedDispatcher(): CoroutineDispatcher = newFixedThreadPoolContext(2, "fixed")
fun scheduledDispatcher(): CoroutineDispatcher = newScheduledThreadPoolContext(2, "scheduled")
fun executorDispatcher(executor: Executor): CoroutineDispatcher = executor.asCoroutineDispatcher()
fun serviceDispatcher(executor: ExecutorService): CoroutineDispatcher = executor.asCoroutineDispatcher()
