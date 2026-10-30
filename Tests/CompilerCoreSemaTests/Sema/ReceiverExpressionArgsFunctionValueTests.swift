@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ReceiverExpressionArgsFunctionValueTests {
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
    func parenthesizedFunctionValuesAcceptExplicitReceiverCalls() throws {
        let diagnostics = try compileAndCollectDiagnostics("""
        fun make(f: Int.(Int) -> Unit): Int.(Int) -> Unit = f

        fun main() {
            val fn: Int.(Int) -> Unit = { _ -> }
            1.(fn)(2)
            1.(make { _ -> })(2)
        }
        """)

        #expect(!diagnostics.hasError, "Got: \(diagnostics.diagnostics)")
    }

    @Test(arguments: [
        """
        class Text

        fun main() {
            val fn: Text.(Int) -> Unit = {}
            1.(fn)(2)
        }
        """,
        """
        class Text

        fun main() {
            val fn: Int.(Text) -> Unit = {}
            1.(fn)(2)
        }
        """,
        """
        fun main() {
            val fn: Int.(Int, Int) -> Unit = { _, _ -> }
            1.(fn)(2)
        }
        """,
        """
        fun main() {
            val fn: (Int, Int) -> Unit = { _, _ -> }
            1.(fn)(2)
        }
        """,
    ])
    func inapplicableFunctionTypesAreRejected(source: String) throws {
        let diagnostics = try compileAndCollectDiagnostics(source)

        #expect(diagnostics.hasError, "Expected the receiver, argument type, or arity mismatch to be rejected")
    }
}
