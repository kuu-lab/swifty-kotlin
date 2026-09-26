@testable import CompilerCore
import Testing

/// Kotlin rejects invoking a nullable function value without `?.`/`!!`;
/// a direct call must not lower a null function object into
/// `kk_function_invoke` (KUU-644).
@Suite
struct NullableFunctionValueCallRejectionTests {

    private func compileAndCollectDiagnostics(_ source: String) throws -> DiagnosticEngine {
        var result: DiagnosticEngine?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = ctx.diagnostics
        }
        return try requireTestValue(result, "Expected diagnostics after Sema")
    }

    @Test
    func nonSafeInvokeOnNullableFunctionPropertyIsRejected() throws {
        // `h?.f` has type `((Int) -> Int)?`, so the non-safe `.invoke` call
        // is illegal — Kotlin wants `h?.f?.invoke(3)`.
        let diagnostics = try compileAndCollectDiagnostics("""
        class Holder(val f: (Int) -> Int)

        fun main() {
            val h: Holder? = null
            println(h?.f.invoke(3))
        }
        """)

        let found = diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" }
        #expect(found, "Expected SEMA-0024 for non-safe invoke on nullable function value, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func directCallOnNullableFunctionPropertyIsRejected() throws {
        // `f` itself is nullable: `h.f(3)` and `h?.f(3)` are both illegal.
        let diagnostics = try compileAndCollectDiagnostics("""
        class Holder(val f: ((Int) -> Int)?)

        fun main() {
            val h = Holder(null)
            println(h.f(3))
        }
        """)

        let found = diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" }
        #expect(found, "Expected SEMA-0024 for direct call on nullable function property, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func safeCallOnNullableFunctionPropertyIsAccepted() throws {
        // The correct Kotlin spelling must still type-check.
        let diagnostics = try compileAndCollectDiagnostics("""
        class Holder(val f: ((Int) -> Int)?)

        fun main() {
            val h = Holder({ it + 1 })
            println(h.f?.invoke(3))
        }
        """)

        let found = diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" }
        #expect(!found, "Unexpected SEMA-0024 for safe invoke on nullable function property, got: \(diagnostics.diagnostics.map(\.code))")
    }
}
