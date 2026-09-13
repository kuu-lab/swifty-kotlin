#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-011 / KSP-661: Validates that `Char.isLetter()` resolves
/// through Sema. The predicate is implemented in bundled Kotlin
/// (kotlin.text.CharPredicates), so it carries no synthetic runtime link.
@Suite
struct CharIsLetterFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testCharIsLetterResolvesInSource
            """
            package sample0

                    fun probe(ch: Char): Boolean {
                        return ch.isLetter()
                    }

                    fun probeLiteral(): Boolean {
                        return 'a'.isLetter()
                    }

            """,
            // testCharIsLetterStubHasCorrectExternalLink
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

            // === testCharIsLetterResolvesInSource ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Char.isLetter() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testCharIsLetterStubHasCorrectExternalLink ===

            do {




                var capturedSema: SemaModule?
                var capturedInterner: StringInterner?

                    capturedSema = try #require(sema)
                    capturedInterner = interner

                let sema = try #require(capturedSema)
                let interner = try #require(capturedInterner)

                let fq = ["kotlin", "text", "isLetter"].map { interner.intern($0) }
                let sym = try #require(
                    sema.symbols.lookupAll(fqName: fq).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == sema.types.charType
                            && signature.parameterTypes.isEmpty
                    },
                    "Expected synthetic kotlin.text.isLetter extension on Char"
                )
                // KSP-661: bundled Kotlin 実装へ移行済みのため合成スタブの外部リンクを持たない。
                #expect(sema.symbols.externalLinkName(for: sym) == nil)

            }

        }
    }

}

#endif
