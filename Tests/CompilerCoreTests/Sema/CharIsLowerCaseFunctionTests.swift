#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-013 / KSP-661: Validates that `kotlin.text.isLowerCase`
/// resolves through Sema as a Char extension (`fun Char.isLowerCase(): Boolean`).
/// The predicate is implemented in bundled Kotlin (kotlin.text.CharPredicates).
@Suite
struct CharIsLowerCaseFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun isLowerOfLiteral(): Boolean {
            return 'a'.isLowerCase()
        }
        """,
        """
        package sample1
        fun isLower(ch: Char): Boolean {
            return ch.isLowerCase()
        }
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    @Test func testIsLowerCaseResolvesOnCharLiteralReceiver() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected isLowerCase to type-check on a Char literal, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIsLowerCaseResolvesOnCharParameterReceiver() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected isLowerCase to type-check on a Char parameter, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
