@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-110/111/114/115: Validates `String.trim`, `trimStart`,
/// `trimEnd`, and `trimMargin` resolve through bundled Kotlin stdlib source.
@Suite
struct StringTrimFunctionTests {
    private static let sources: [String] = [
        """
        package sample0

        fun trimDefault(s: String): String {
            return s.trim()
        }

        fun trimWithPredicate(s: String): String {
            return s.trim { it == 'x' }
        }
        """,
        """
        package sample1

        fun stripLeadingWhitespace(s: String): String {
            return s.trimStart()
        }

        fun stripLeadingX(s: String): String {
            return s.trimStart { it == 'x' }
        }
        """,
        """
        package sample2

        fun trimWhitespace(s: String): String {
            return s.trimEnd()
        }

        fun trimWithPredicate(s: String): String {
            return s.trimEnd { it == 'x' }
        }

        fun trimWithNamedPredicate(s: String): String {
            return s.trimEnd(predicate = { ch -> ch == ' ' || ch == '\\t' })
        }
        """,
        """
        package sample3

        fun stripDefaultMargin(s: String): String {
            return s.trimMargin()
        }

        fun stripGreaterThanMargin(s: String): String {
            return s.trimMargin(">")
        }
        """,
    ]

    @Test
    func testTrimFunctionsResolveInSource() throws {
        try withTemporaryFiles(contents: Self.sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected trim/trimStart/trimEnd/trimMargin to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }
}
