@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-110/111/112: Consolidated Sema coverage for `kotlin.text.String.trim`,
/// `trimStart`, `trimEnd`, `trimMargin`, and `trimIndent`. A single `runSema(ctx)`
/// resolves all source packages and each source is checked for expected diagnostics.
@Suite
struct StringTrimFunctionTests {
    @Test
    func testTrimFunctionsResolveInSource() throws {
        let sources: [String] = [
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
            """
            package sample4
            fun main() {
                val literal: String = "    hello".trimIndent()
                val source: String = "  line"
                val dedented: String = source.trimIndent()
                val returnIsString: Int = "    abcde".trimIndent().length
                val chained: String = "  abc".trimIndent().trim()
            }
            """,
            """
            package sample5
            fun main() {
                val s = "abc".trimIndent(1)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let names = ["trim", "trimStart", "trimEnd", "trimMargin"]
            for (index, name) in names.enumerated() {
                let path = paths[index]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                let errors = pathDiagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected \(name) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // === trimIndent ===
            do {

                let sample4Path = paths[4]
                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)
                #expect(
                    !(sample4Diagnostics.contains { $0.severity == .error }),
                    "resolve: \(sample4Diagnostics)"
                )

                let sample5Path = paths[5]
                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)
                #expect(
                    sample5Diagnostics.contains { $0.severity == .error },
                    "expected error for extra argument, got: \(sample5Diagnostics)"
                )
            }
        }
    }
}
