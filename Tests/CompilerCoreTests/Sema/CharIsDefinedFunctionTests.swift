#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-004 / KSP-661: Validates that `Char.isDefined()` resolves
/// through Sema for plain Char receivers as well as literal and branch contexts.
/// The predicate is implemented in bundled Kotlin (kotlin.text.CharPredicates),
/// so the resolved symbol carries no synthetic runtime link.
@Suite
struct CharIsDefinedFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testCharIsDefinedResolvesInSource
            """
            package sample0

                    fun definedCheck(ch: Char): Boolean {
                        return ch.isDefined()
                    }

                    fun definedCheckLiteral(): Boolean {
                        return 'A'.isDefined()
                    }

                    fun definedCheckSurrogate(): Boolean {
                        return '\\uD800'.isDefined()
                    }

                    fun definedCheckIfBranch(ch: Char): Int {
                        return if (ch.isDefined()) 1 else 0
                    }

            """,
            // testCharIsDefinedResolvesToRuntimeLink
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

            // === testCharIsDefinedResolvesInSource ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Char.isDefined() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testCharIsDefinedResolvesToRuntimeLink ===

            do {




                var resolvedLink: String?

                    let fq = ["kotlin", "text", "isDefined"].map { interner.intern($0) }
                    let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == sema.types.charType
                            && signature.parameterTypes.isEmpty
                    })
                    resolvedLink = sema.symbols.externalLinkName(for: symbol)
                    #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isDefined() should return Boolean")

                // KSP-661: bundled Kotlin 実装へ移行済みのため合成スタブの外部リンクを持たない。
                #expect(resolvedLink == nil)

            }

        }
    }

}

#endif
