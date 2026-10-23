@testable import CompilerCore
import Testing

/// KUU-3007: Kotlin function declarations need `::` before they can be used as values.
@Suite
struct TopLevelFunctionInvocationSyntaxTests {

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
    func bareTopLevelAndLocalFunctionsAreRejectedAsValues() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun f() = 1
        val g = f

        fun main() {
            val p = println
            listOf(1).forEach(println)
            println(assert)
            fun localFunction() = 2
            val localValue = localFunction
        }
        """)

        let errors = diagnostics.diagnostics.filter { $0.severity == .error }
        let invocationErrors = errors.filter { $0.code == "KSWIFTK-SEMA-0309" }
        #expect(invocationErrors.count == 5, "Expected one invocation-required diagnostic per bare function, got: \(errors)")
    }

    @Test
    func callableReferencesAndDirectInvocationsRemainValid() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun f() = 1

        fun main() {
            val g = ::f
            println(g())
            println(f())
            fun localFunction() = 2
            val local = ::localFunction
            println(local())
        }
        """)

        let errors = diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors for explicit invocations and callable references: \(errors)")
    }

    @Test
    func localExtensionFunctionShadowsTopLevelExtensionWithoutBareValueError() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun Int.twice(): Int = this * 100

        fun main() {
            fun Int.twice(): Int = this * 2
            println(3.twice())
        }
        """)

        let errors = diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "A local extension call must shadow the top-level one, got: \(errors)")
    }
}
