@testable import CompilerCore
import Foundation
import Testing

/// KUU-1351: `onErrorReturn`/`onErrorResume`/`delayEach` are not
/// kotlinx-coroutines `Flow` operators (kotlinx has `catch`/`retry`/`retryWhen`
/// for error handling and `debounce`/`sample`/`onEach`+`delay` for timing).
/// The compiler-synthesized fallback admitted them, so KSwiftK accepted code
/// that kotlinc rejects as unresolved. These calls must now produce member
/// resolution errors on every Flow receiver shape.
@Suite
struct FlowMemberAvailabilityTests {
    @Test
    func phantomFlowMembersAreRejectedOnFlowReceiver() throws {
        let expressions = [
            "f.onErrorReturn { 9 }",
            "f.onErrorResume { flowOf(0) }",
            "f.onErrorResume(flowOf(0))",
            "f.delayEach(10)",
            "flowOf(1, 2).onErrorReturn { 9 }",
            "flowOf(1).onErrorResume { flowOf(0) }",
            "flowOf(1).delayEach(10)",
            "flow { emit(1) }.delayEach(10)",
            "flow { emit(1) }.map { it }.onErrorReturn { 0 }",
            "listOf(1).asFlow().delayEach(5)",
        ]
        let sources = expressions.enumerated().map { index, expression in
            """
            package rejected\(index)
            import kotlinx.coroutines.flow.*
            fun probe(f: Flow<Int>) {
                \(expression)
            }
            """
        }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for (index, path) in paths.enumerated() {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(!errors.isEmpty, "Expected rejection of \(expressions[index])")
                #expect(
                    errors.contains { [
                        "KSWIFTK-SEMA-0002", "KSWIFTK-SEMA-0022", "KSWIFTK-SEMA-0023",
                        "KSWIFTK-SEMA-0024", "KSWIFTK-TYPE-0001",
                    ].contains($0.code) },
                    "Expected member resolution diagnostic for \(expressions[index]), got \(errors)"
                )
            }
        }
    }

    @Test
    func realFlowOperatorsRemainAvailable() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*
        fun failOnTwo(value: Int): Int {
            if (value == 2) throw RuntimeException("boom")
            return value
        }
        fun main() {
            runBlocking {
                val f: Flow<Int> = flowOf(1, 2, 3)
                val mapped = f.map { it * 2 }
                val filtered = f.filter { it > 1 }
                val taken = f.take(2)
                val caught = flow { emit(1); emit(2) }
                    .map(::failOnTwo)
                    .catch { _: Throwable -> println(-1) }
                val retried = flow { emit(1) }.retry(1)
                val retriedWhen = flow { emit(7) }
                    .map(::failOnTwo)
                    .retryWhen { _: Throwable, attempt: Long -> attempt < 1L }
                println(mapped.toList())
                println(filtered.toList())
                println(taken.toList())
                println(caught.toList())
                println(retried.toList())
                println(retriedWhen.toList())
                println(f.first())
                f.collect { println(it) }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected valid Flow calls to keep resolving: \(errors)")
        }
    }
}
