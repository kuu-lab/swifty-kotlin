#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-005 / KSP-661: Validates that `Char.isDigit()` resolves
/// through Sema for plain Char receivers as well as literal / branch contexts.
/// The predicate is implemented in bundled Kotlin (kotlin.text.CharPredicates),
/// so the resolved symbol carries no synthetic runtime link.
@Suite
struct CharIsDigitFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testCharIsDigitResolvesInSource
            """
            package sample0

                    fun digitCheck(ch: Char): Boolean {
                        return ch.isDigit()
                    }

                    fun digitCheckLiteral(): Boolean {
                        return '7'.isDigit()
                    }

                    fun digitCheckNonDigit(): Boolean {
                        return 'A'.isDigit()
                    }

                    fun digitCheckIfBranch(ch: Char): Int {
                        return if (ch.isDigit()) 1 else 0
                    }

            """,
            // testCharIsDigitResolvesToRuntimeLink
            """
            package sample1
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testCharIsDigitResolvesInSource ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Char.isDigit() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testCharIsDigitResolvesToRuntimeLink ===

            do {




                var resolvedLink: String?

                    let fq = ["kotlin", "text", "isDigit"].map { interner.intern($0) }
                    let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == sema.types.charType
                            && signature.parameterTypes.isEmpty
                    })
                    resolvedLink = sema.symbols.externalLinkName(for: symbol)
                    #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isDigit() should return Boolean")

                // KSP-661: bundled Kotlin 実装へ移行済みのため合成スタブの外部リンクを持たない。
                #expect(resolvedLink == nil)

            }

        }
    }

}

#endif
