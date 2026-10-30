#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct WhenElseBranchPositionTests {
    @Test
    func rejectsBranchesAfterElseInExpressionAndStatementForms() throws {
        let source = """
        fun subjectExpression(value: Int): Int = when (value) { else -> 1; 1 -> 2 }
        fun subjectlessExpression(): Int = when { else -> 1; true -> 2 }
        fun statement(value: Int) {
            when (value) { else -> println(1); 1 -> println(2) }
        }
        fun repeatedElse(): Int = when (1) { else -> 1; else -> 2 }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let elsePositionErrors = errors.filter { $0.code == "KSWIFTK-PARSE-0027" }
        #expect(elsePositionErrors.count == 4, "Got: \(errors)")
        #expect(elsePositionErrors.allSatisfy {
            $0.message == "The 'else' branch must be the last branch in a 'when' expression."
        })
    }

    @Test
    func acceptsElseAsTheFinalWhenBranch() throws {
        let source = """
        fun subjectExpression(value: Int): Int = when (value) { 1 -> 2; else -> 1 }
        fun subjectlessExpression(): Int = when { true -> 2; else -> 1 }
        fun statement(value: Int) {
            when (value) { 1 -> println(2); else -> println(1) }
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
