@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-027/029/030: Consolidated Sema coverage for `String.isBlank`,
/// `isNotBlank`, and `isNotEmpty`. A single `runSema(ctx)` resolves all source
/// packages and each `do` block verifies the expected symbol and lack of a C
/// external link.
@Suite
struct StringBlankOrEmptyFunctionTests {
    @Test
    func testBlankAndEmptyFunctionsResolveInSource() throws {
        let sources: [String] = [
            """
            package sample0
            fun isStringBlank(s: String): Boolean {
                return s.isBlank()
            }

            fun isBlankLiteral(): Boolean {
                return "   ".isBlank()
            }

            fun isNonBlankLiteral(): Boolean {
                return "hello".isBlank()
            }

            fun isEmptyStringBlank(): Boolean {
                return "".isBlank()
            }
            """,
            """
            package sample1
            fun stringHasContent(value: String): Boolean {
                return value.isNotBlank()
            }

            fun charSequenceHasContent(value: CharSequence): Boolean {
                return value.isNotBlank()
            }

            fun literalHasContent(): Boolean {
                return "hello".isNotBlank()
            }
            """,
            """
            package sample2
            fun stringHasContent(value: String): Boolean {
                return value.isNotEmpty()
            }

            fun charSequenceHasContent(value: CharSequence): Boolean {
                return value.isNotEmpty()
            }

            fun literalHasContent(): Boolean {
                return "hello".isNotEmpty()
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for path in paths {
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                let errors = pathDiagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected blank/empty checks to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // === isBlank ===
            do {
                let path = paths[0]
                let fqName = ["kotlin", "text", "isBlank"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.text.isBlank to be registered"
                )
                #expect(
                    sema.symbols.externalLinkName(for: symbol) == nil,
                    "Expected isBlank extension to be bundled Kotlin without a C external link"
                )
                _ = (path, ast)
            }

            // === isNotBlank ===
            do {
                let path = paths[1]
                let fqName = ["kotlin", "text", "isNotBlank"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.text.isNotBlank to be registered"
                )
                #expect(
                    sema.symbols.externalLinkName(for: symbol) == nil,
                    "Expected isNotBlank extension to be bundled Kotlin without a C external link"
                )
                _ = path
            }

            // === isNotEmpty ===
            do {
                let path = paths[2]
                let fqName = ["kotlin", "text", "isNotEmpty"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.text.isNotEmpty to be registered"
                )
                #expect(
                    sema.symbols.externalLinkName(for: symbol) == nil,
                    "Expected isNotEmpty extension to be bundled Kotlin without a C external link"
                )
                _ = path
            }
        }
    }
}
