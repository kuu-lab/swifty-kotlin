@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendCoroutineDispatcherTests {
    @Test(arguments: [(false, false), (false, true), (true, true)])
    func nestedWithContextPreservesCapturedResults(
        optimized: Bool,
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try assertKotlinOutput("""
        import kotlinx.coroutines.*
        fun main() {
            runBlocking {
                println(withContext(Dispatchers.Default) {
                    withContext(Dispatchers.IO) { "nested" }
                })
                val prefix = "captured"
                val value = 40
                println(withContext(Dispatchers.Default) {
                    withContext(Dispatchers.IO) {
                        delay(1)
                        "$prefix:${value + 2}"
                    }
                })
                println("resumed")
            }
        }
        """, moduleName: "NestedWithContext", expected: """
        nested
        captured:42
        resumed

        """, optLevel: optimized ? .O2 : .O0, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
    }

    @Test(arguments: [false, true])
    func aliasesPreserveDispatcherHandles(allowDefaultStdlibLibrary: Bool) throws {
        try assertKotlinOutput("""
        import kotlinx.coroutines.*
        import java.lang.Runnable
        import java.util.concurrent.Callable
        import java.util.concurrent.Executor
        import java.util.concurrent.ExecutorService
        import java.util.concurrent.Future
        import java.util.concurrent.FutureTask
        import java.util.concurrent.TimeUnit

        class Service : ExecutorService {
            override fun execute(command: Runnable) { command.run() }
            override fun shutdown() {}
            override fun shutdownNow(): List<Runnable> = emptyList()
            override val isShutdown: Boolean = false
            override val isTerminated: Boolean = false
            override fun awaitTermination(timeout: Long, unit: TimeUnit): Boolean = true
            override fun <T> submit(task: Callable<T>): Future<T> = FutureTask(task)
            override fun submit(task: Runnable): Future<*> =
                FutureTask<Unit>(Callable { task.run() })
            override fun <T> submit(task: Runnable, result: T): Future<T> =
                FutureTask(Callable { task.run(); result })
            override fun <T> invokeAll(tasks: Collection<Callable<T>>): List<Future<T>> =
                tasks.map { submit(it) }
            override fun <T> invokeAny(tasks: Collection<Callable<T>>): T =
                submit(tasks.first()).get()
        }

        fun main() {
            val default = Dispatchers.Default
            println(Dispatchers.IO === default)
            println(Dispatchers.Unconfined === default)
            println(default.limitedParallelism(1) === default)
            println(Dispatchers.Main.immediate === Dispatchers.Main)
            println(newSingleThreadContext("single") === default)
            println(newFixedThreadPoolContext(2, "fixed") === default)
            println(newScheduledThreadPoolContext(2, "scheduled") === default)
            val service: ExecutorService = Service()
            val executor: Executor = service
            println(service.asCoroutineDispatcher() === default)
            println(executor.asCoroutineDispatcher() === default)
            executor.execute(Runnable { println("executed") })
            runBlocking {
                println(withContext(Dispatchers.IO.limitedParallelism(2)) { 42 })
                println(withContext(Dispatchers.Unconfined) { 43 })
                println(withContext(newSingleThreadContext("worker")) { 44 })
            }
        }
        """, moduleName: "CoroutineDispatcherAliases", expected: """
        false
        false
        false
        false
        true
        true
        true
        false
        false
        executed
        42
        43
        44

        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
    }

    @Test
    func invalidParallelismAndThreadCountsThrow() throws {
        try assertKotlinOutput("""
        import kotlinx.coroutines.*

        fun main() {
            for (count in listOf(0, -1)) {
                try { Dispatchers.Default.limitedParallelism(count) }
                catch (e: IllegalArgumentException) { println("parallelism rejected") }
                try { newFixedThreadPoolContext(count, "fixed") }
                catch (e: IllegalArgumentException) { println("fixed rejected") }
                try { newScheduledThreadPoolContext(count, "scheduled") }
                catch (e: IllegalArgumentException) { println("scheduled rejected") }
            }
        }
        """, moduleName: "CoroutineDispatcherValidation", expected: """
        parallelism rejected
        fixed rejected
        scheduled rejected
        parallelism rejected
        fixed rejected
        scheduled rejected

        """)
    }
}
