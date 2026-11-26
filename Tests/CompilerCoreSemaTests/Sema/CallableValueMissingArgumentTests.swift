@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableValueMissingArgumentTests {

    private func compileAndCollectDiagnostics(_ source: String) throws -> DiagnosticEngine {
        var result: DiagnosticEngine?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            result = ctx.diagnostics
        }
        return try requireTestValue(result, "Expected diagnostics after Sema")
    }

    @Test
    func missingArgumentOnFunctionTypedValueUsesSynthesizedName() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun main() {
            val f: (Int) -> Unit = { }
            f()
        }
        """)

        let found = diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0480" && $0.message == "No value passed for parameter 'p1'."
        }
        #expect(found, "Expected SEMA-0480 for missing function-value argument, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func missingSecondArgumentOnFunctionTypedValue() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun main() {
            val g: (Int, String) -> Unit = { _, _ -> }
            g(1)
        }
        """)

        let found = diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0480" && $0.message == "No value passed for parameter 'p2'."
        }
        #expect(found, "Expected SEMA-0480 for second missing function-value argument, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func aritySatisfiedCallOnFunctionTypedValueIsAccepted() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun main() {
            val f: (Int) -> Unit = { }
            f(1)
        }
        """)

        let found = diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0480" }
        #expect(!found, "Unexpected SEMA-0480 for arity-satisfied function-value call, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func missingArgumentOnCallableReferenceKeepsSynthesizedName() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun two(a: Int, b: String) = "$a $b"

        fun main() {
            val h = ::two
            h(1)
        }
        """)

        let found = diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0480" && $0.message == "No value passed for parameter 'p2'."
        }
        #expect(found, "Expected SEMA-0480 for missing callable-reference argument, got: \(diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func missingArgumentOnOrdinaryCallReportsDeclaredName() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun two(a: Int, b: String) = "$a $b"

        fun main() {
            two(b = "x")
        }
        """)

        let found = diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0480" && $0.message == "No value passed for parameter 'a'."
        }
        #expect(found, "Expected SEMA-0480 naming the missing parameter, got: \(diagnostics.diagnostics.map(\.code))")
    }
}
