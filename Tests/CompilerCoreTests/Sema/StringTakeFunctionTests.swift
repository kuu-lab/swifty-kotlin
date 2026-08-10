@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-078/080/081: Consolidated Sema coverage for `String.take`,
/// `takeLast`, and `takeLastWhile` for `String` receivers. A single `runSema(ctx)`
/// resolves all source packages and each package is checked for the absence of errors.
@Suite
struct StringTakeFunctionTests {
    @Test func testTakeFunctionsResolveInSource() throws {
        let sources: [String] = [
            """
            package sample0
            fun firstThree(s: String): String {
                return s.take(3)
            }

            fun takeLiteral(): String {
                return "hello world".take(5)
            }

            fun takeFromExpression(value: Int): String {
                return value.toString().take(2)
            }

            fun takeAll(s: String): String {
                return s.take(s.length)
            }
            """,
            """
            package sample1
            fun lastThree(): String {
                return "hello".takeLast(3)
            }

            fun suffix(s: String, n: Int): String {
                return s.takeLast(n)
            }

            fun lastHalf(s: String): String {
                return s.takeLast(s.length / 2)
            }

            fun greetingTail(name: String): String {
                return "Hello, ${name}!".takeLast(6)
            }
            """,
            """
            package sample2
            fun trailingLetters(s: String): String {
                return s.takeLastWhile { it.isLetter() }
            }

            fun trailDigits(): String {
                return "abc123".takeLastWhile { it.isDigit() }
            }

            fun trailingLower(s: String): String {
                return s.takeLastWhile { it.isLowerCase() }
            }

            fun trimmedSuffix(s: String): String {
                return s.trim().takeLastWhile { it != ' ' }
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let names = ["take", "takeLast", "takeLastWhile"]
            for (index, name) in names.enumerated() {
                let path = paths[index]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                let errors = pathDiagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected \(name) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }
}
