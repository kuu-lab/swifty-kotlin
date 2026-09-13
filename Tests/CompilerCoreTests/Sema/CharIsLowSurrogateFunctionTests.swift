#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-014: Validates that `Char.isLowSurrogate()` resolves through
/// Sema for plain Char receivers as well as literal / branch contexts.
/// KSP-663: this is backed by bundled Kotlin source and has no synthetic runtime link.
@Suite
struct CharIsLowSurrogateFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testCharIsLowSurrogateResolvesInSource
            """
            package sample0

                    fun lowSurrogateCheck(ch: Char): Boolean {
                        return ch.isLowSurrogate()
                    }

                    fun lowSurrogateCheckLiteralLow(): Boolean {
                        return '\\uDC00'.isLowSurrogate()
                    }

                    fun lowSurrogateCheckLiteralHigh(): Boolean {
                        return '\\uD800'.isLowSurrogate()
                    }

                    fun lowSurrogateCheckLiteralPlain(): Boolean {
                        return 'A'.isLowSurrogate()
                    }

                    fun lowSurrogateCheckIfBranch(ch: Char): Int {
                        return if (ch.isLowSurrogate()) 1 else 0
                    }

            """,
            // testCharIsLowSurrogateResolvesToRuntimeLink
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

            // === testCharIsLowSurrogateResolvesInSource ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Char.isLowSurrogate() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testCharIsLowSurrogateResolvesToSourceFunction ===

            do {




                var resolvedLink: String?

                    let fq = ["kotlin", "text", "isLowSurrogate"].map { interner.intern($0) }
                    let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == sema.types.charType
                            && signature.parameterTypes.isEmpty
                    })
                    resolvedLink = sema.symbols.externalLinkName(for: symbol)
                    #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isLowSurrogate() should return Boolean")

                #expect(sema.symbols.symbol(symbol)?.declSite != nil, "Char.isLowSurrogate() should be backed by Kotlin source")
                #expect(resolvedLink == nil, "Char.isLowSurrogate() should have no C external link")

            }

        }
    }

}

#endif
