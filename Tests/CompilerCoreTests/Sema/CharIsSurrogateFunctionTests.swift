#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-015: Validates that `Char.isSurrogate()` resolves through
/// Sema for plain Char receivers as well as literal / branch contexts.
/// KSP-663: this is backed by bundled Kotlin source and has no synthetic runtime link.
/// It returns true for the entire surrogate range `[0xD800, 0xDFFF]`.
@Suite
struct CharIsSurrogateFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testCharIsSurrogateResolvesInSource
            """
            package sample0

                    fun surrogateCheck(ch: Char): Boolean {
                        return ch.isSurrogate()
                    }

                    fun surrogateCheckHighLiteral(): Boolean {
                        return '\\uD800'.isSurrogate()
                    }

                    fun surrogateCheckLowLiteral(): Boolean {
                        return '\\uDFFF'.isSurrogate()
                    }

                    fun surrogateCheckNonSurrogate(): Boolean {
                        return 'A'.isSurrogate()
                    }

                    fun surrogateCheckIfBranch(ch: Char): Int {
                        return if (ch.isSurrogate()) 1 else 0
                    }

            """,
            // testCharIsSurrogateResolvesToRuntimeLink
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

            // === testCharIsSurrogateResolvesInSource ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Char.isSurrogate() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testCharIsSurrogateResolvesToSourceFunction ===

            do {




                var resolvedLink: String?

                    let fq = ["kotlin", "text", "isSurrogate"].map { interner.intern($0) }
                    let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == sema.types.charType
                            && signature.parameterTypes.isEmpty
                    })
                    resolvedLink = sema.symbols.externalLinkName(for: symbol)
                    #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isSurrogate() should return Boolean")

                #expect(sema.symbols.symbol(symbol)?.declSite != nil, "Char.isSurrogate() should be backed by Kotlin source")
                #expect(resolvedLink == nil, "Char.isSurrogate() should have no C external link")

            }

        }
    }

}

#endif
