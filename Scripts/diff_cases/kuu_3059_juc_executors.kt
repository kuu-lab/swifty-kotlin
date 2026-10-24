import java.util.concurrent.Callable
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

// KUU-3059: executor/future surface. The worker computes off-thread but the
// main thread blocks on get(), so the printed sequence is deterministic.
fun main() {
    val executor = Executors.newFixedThreadPool(2)
    val future = executor.submit(Callable { 40 + 2 })
    println(future.get(30, TimeUnit.SECONDS)) // 42
    println(future.isDone)                  // true
    println(executor.isShutdown)            // false
    executor.shutdown()
    println(executor.isShutdown)            // true
    println(executor.awaitTermination(30, TimeUnit.SECONDS)) // true
    println(executor.isTerminated)          // true

    val single = Executors.newSingleThreadExecutor()
    val submitted = single.submit(Callable { "ran" })
    println(submitted.get())                  // ran
    single.shutdown()
    println(single.awaitTermination(30, TimeUnit.SECONDS)) // true

    val task = FutureTask(Callable { "task-result" })
    println(task.isDone)                    // false
    task.run()
    println(task.get())                       // task-result
    println(task.isDone)                    // true

    println(CompletableFuture.completedFuture(1).get())          // 1
    println(CompletableFuture.completedFuture("s").join())       // s
    println(CompletableFuture.completedFuture(2)
        .thenApply { it * 10 }.get())                            // 20
    println(CompletableFuture.completedFuture(3)
        .thenCompose { CompletableFuture.completedFuture(it + 4) }.get()) // 7

    val incomplete = CompletableFuture<Int>()
    try {
        incomplete.get(50, TimeUnit.MILLISECONDS)
        println("unreachable")
    } catch (e: java.util.concurrent.TimeoutException) {
        println("timeout")                    // timeout
    }
}
