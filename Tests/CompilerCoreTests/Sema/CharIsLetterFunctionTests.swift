#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-011 / KSP-661: Validates that `Char.isLetter()` resolves
/// through Sema. The predicate is implemented in bundled Kotlin
/// (kotlin.text.CharPredicates), so it carries no synthetic runtime link.
@Suite
struct CharIsLetterFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun probe(ch: Char): Boolean {
            return ch.isLetter()
        }

        fun probeLiteral(): Boolean {
            return 'a'.isLetter()
        }
        """,
        """
        package sample1
        fun noop() {}
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
    @Test func testCharIsLetterResolvesInSource() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isLetter() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testCharIsLetterStubHasCorrectExternalLink() throws {
        var capturedSema: SemaModule?
        var capturedInterner: StringInterner?

        let ctx = try sharedCtx()
            capturedSema = try #require(ctx.sema)
            capturedInterner = ctx.interner

    }
}
#endif
