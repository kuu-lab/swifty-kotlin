#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Sema regressions for receiver-bearing coroutine launcher function values (#7513).
/// Negative diagnostics and user-defined builder shadowing are not visible to
/// diff_kotlinc, so they stay as unit tests.
@Suite
struct CoroutineLauncherFunctionValueTests {
    @Test
    func coroutineLauncherFunctionValueResultTypesAreNotOverriddenByExpectedType() throws {
        let source = """
        import kotlinx.coroutines.*
        fun main() = runBlocking {
            val block: suspend CoroutineScope.() -> Int = { 42 }
            val wrong: String = withContext(Dispatchers.Default, block = block)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test
    func userDefinedCoroutineBuilderNamePreservesDeclaredReturnType() throws {
        let source = """
        import kotlinx.coroutines.CoroutineScope
        fun runBlocking(block: suspend CoroutineScope.() -> Int): String = "custom"
        fun main() {
            val block: suspend CoroutineScope.() -> Int = { 42 }
            val result: String = runBlocking(block = block)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func coroutineLaunchersAcceptReceiverFunctionValues() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() {
            val root: suspend CoroutineScope.() -> Int = { 42 }
            val result: Int = runBlocking(block = root)
            runBlocking {
                var side = 0
                val f: suspend CoroutineScope.() -> Unit = { side = 5 }
                launch(block = f).join()
                launch(Dispatchers.Default, block = f).join()
                launch(start = CoroutineStart.LAZY, block = f).join()
                val scope: CoroutineScope = this
                scope.launch(block = f).join()
                val g: suspend CoroutineScope.() -> Int = { side + 7 }
                val value: Int = async(block = g).await()
                val task: Deferred<Int> = async(block = g)
                val savedValue: Int = task.await()
                val lazyValue: Int = async(start = CoroutineStart.LAZY, block = g).await()
                val switched: Int = withContext(Dispatchers.Default, block = g)
                val timed: Int = withTimeout(1000L, block = g)
                val nullable: Int? = withTimeoutOrNull(1000L, block = g)
                val nullableBlock: suspend CoroutineScope.() -> Int? = { null }
                val nullableTimed: Int? = withTimeout(1000, block = nullableBlock)
                val nullableOrNull: Int? = withTimeoutOrNull(1000, block = nullableBlock)
                val timeoutScope: CoroutineScope = withTimeout(1000) { this }
                val nullableTimeoutScope: CoroutineScope? = withTimeoutOrNull(1000) { this }
                val nullableTask: Deferred<Int?> = async(block = nullableBlock)
                val nullableValue: Int? = nullableTask.await()
                val literalTask: Deferred<Int> = async { 11 }
                val literalValue: Int = literalTask.await()
                val nullableLiteralTask: Deferred<Int?> = async { null as Int? }
                val nullableLiteralValue: Int? = nullableLiteralTask.await()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
