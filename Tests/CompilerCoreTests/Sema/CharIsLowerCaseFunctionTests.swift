#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-013 / KSP-661: Validates that `kotlin.text.isLowerCase`
/// resolves through Sema as a Char extension (`fun Char.isLowerCase(): Boolean`).
/// The predicate is implemented in bundled Kotlin (kotlin.text.CharPredicates).
@Suite
struct CharIsLowerCaseFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testIsLowerCaseResolvesOnCharLiteralReceiver
            """
            package sample0

                    fun isLowerOfLiteral(): Boolean {
                        return 'a'.isLowerCase()
                    }

            """,
            // testIsLowerCaseResolvesOnCharParameterReceiver
            """
            package sample1

                    fun isLower(ch: Char): Boolean {
                        return ch.isLowerCase()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            _ = try #require(ctx.sema)


            // === testIsLowerCaseResolvesOnCharLiteralReceiver ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected isLowerCase to type-check on a Char literal, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testIsLowerCaseResolvesOnCharParameterReceiver ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected isLowerCase to type-check on a Char parameter, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

        }
    }

}

#endif
