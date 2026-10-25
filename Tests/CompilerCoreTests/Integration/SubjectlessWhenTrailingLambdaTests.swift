#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SubjectlessWhenTrailingLambdaTests {
    @Test
    func compilesTrailingLambdaCallAsSubjectlessWhenCondition() throws {
        let source = """
        internal interface List<T>

        internal fun <T> List<T>.any(predicate: (T) -> Boolean): Boolean = false

        internal typealias IntAdjustment = (List<Int>) -> Int

        internal val answer: IntAdjustment = { xs ->
            when {
                xs.any { it > 0 } -> 1
                else -> 0
            }
        }

        internal val parenthesizedAnswer: IntAdjustment = { xs ->
            when {
                xs.any({ it > 0 }) -> 1
                else -> 0
            }
        }

        internal val ifAnswer: IntAdjustment = { xs ->
            if (xs.any { it > 0 }) 1 else 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
