#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct KotlinxCoroutinesZipInferenceTests {
    @Test
    func combineAndSelectCallShapesInferWithoutStdlib() throws {
        let sources = [
            """
            package flowtest.internal

            import flowtest.Flow
            import flowtest.FlowCollector

            internal suspend fun <R, T> FlowCollector<R>.combineInternal(
                flows: Array<out Flow<T>>,
                arrayFactory: () -> Array<T?>?,
                transform: suspend FlowCollector<R>.(Array<T>) -> Unit
            ) { }
            """,
            """
            package flowtest

            import flowtest.internal.*
            import flowtest.selects.ReceiveChannel
            import flowtest.selects.select

            interface Flow<out T>
            interface FlowCollector<R> { suspend fun emit(value: R) }

            fun <T> arrayOf(vararg values: T): Array<out T> = values
            private fun <T> nullArrayFactory(): () -> Array<T>? = { null }
            fun <T> safeFlow(block: suspend FlowCollector<T>.() -> Unit): Flow<T> = null as Flow<T>

            fun <T1, T2, R> Flow<T1>.combineProbe(
                other: Flow<T2>, transform: suspend (T1, T2) -> R
            ): Flow<R> = safeFlow {
                combineInternal(
                    arrayOf(this@combineProbe, other),
                    nullArrayFactory(),
                    { emit(transform(it[0] as T1, it[1] as T2)) }
                )
            }

            fun <T, R> combineProbe(
                flows: Array<out Flow<T>>, transform: suspend (Array<T>) -> R
            ): Flow<R> = safeFlow {
                combineInternal(flows, nullArrayFactory(), { emit(transform(it)) })
            }

            fun <T, R> combineTransformProbe(
                flows: Array<out Flow<T>>,
                transform: suspend FlowCollector<R>.(Array<T>) -> Unit
            ): Flow<R> = safeFlow {
                combineInternal(flows, nullArrayFactory(), { transform(it) })
            }

            suspend fun <T> FlowCollector<T>.selectProbe(values: ReceiveChannel<T>) {
                var open = true
                var pending = false
                var last: T? = null
                while (open) {
                    select<Unit> {
                        values.onReceiveCatching { result ->
                            if (result.isSuccess) {
                                last = result.getOrThrow()
                                pending = true
                            } else {
                                if (pending) {
                                    emit(last as T)
                                    pending = false
                                    last = null
                                }
                                open = false
                            }
                        }
                    }
                }
            }
            """,
            """
            package flowtest.selects

            interface ChannelResult<T> {
                val isSuccess: Boolean
                fun getOrThrow(): T
            }
            interface ReceiveChannel<E>

            interface SelectBuilder<R> {
                fun <E> ReceiveChannel<E>.onReceiveCatching(block: suspend (ChannelResult<E>) -> R)
            }
            suspend fun <R> select(builder: SelectBuilder<R>.() -> Unit): R = null as R
            """,
            "package kotlin\nobject Unit",
        ]
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let paths = sources.indices.map { tempDir.appendingPathComponent("input\($0).kt").path }
        let ctx = makeCompilationContext(
            inputs: paths,
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected the kotlinx.coroutines combine/select call shapes to infer without errors: \(ctx.diagnostics.render(ctx.sourceManager))"
        )
    }
}
#endif
