#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

extension CompilerCoreTests {
    /// KUU-4252: vendored Flow declarations shadow their imported stdlib twins
    /// while the trailing lambda selects the suspend-function collect overload.
    @Test func testVendoredFlowCollectTrailingLambdaResolves() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        package kotlinx.coroutines.flow

        public interface Flow<out T>

        public fun interface FlowCollector<in T> {
            public suspend fun emit(value: T)
        }

        public suspend fun <T> Flow<T>.collect(collector: suspend (T) -> Unit) {}

        public suspend fun <T> Flow<T>.collect(collector: FlowCollector<T>) {}

        private class Kuu4252Collector<T> : FlowCollector<T> {
            override suspend fun emit(value: T) {}
        }

        private class Kuu4252Abort(val owner: Any) : Throwable()

        fun <T, R> Flow<T>.kuu4252TransformWhile(
            action: suspend FlowCollector<R>.(T) -> Boolean
        ): Flow<R> {
            val source = this
            return flow {
                val collector = Kuu4252Collector<R>()
                try {
                    source.collect { value ->
                        if (!action(collector, value)) throw Kuu4252Abort(collector)
                    }
                } catch (e: Kuu4252Abort) {
                    if (e.owner !== collector) throw e
                }
            }
        }
        """, moduleName: "kotlinx-coroutines-core", allowDefaultStdlibLibrary: true)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
    }
}
#endif
