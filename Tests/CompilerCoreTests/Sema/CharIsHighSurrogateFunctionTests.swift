#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-006: Validates that `Char.isHighSurrogate()` resolves through
/// Sema for plain Char receivers as well as literal / branch contexts.
/// KSP-663: this is backed by bundled Kotlin source and has no synthetic runtime link.
@Suite
struct CharIsHighSurrogateFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testCharIsHighSurrogateResolvesInSource
            """
            package sample0

                    fun highSurrogateCheck(ch: Char): Boolean {
                        return ch.isHighSurrogate()
                    }

                    fun highSurrogateCheckLiteral(): Boolean {
                        return 'A'.isHighSurrogate()
                    }

                    fun highSurrogateCheckBoundary(): Boolean {
                        return '\\uD800'.isHighSurrogate()
                    }

                    fun highSurrogateCheckIfBranch(ch: Char): Int {
                        return if (ch.isHighSurrogate()) 1 else 0
                    }

            """,
            // testCharIsHighSurrogateResolvesToRuntimeLink
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

            // === testCharIsHighSurrogateResolvesInSource ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Char.isHighSurrogate() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testCharIsHighSurrogateResolvesToSourceFunction ===

            do {




                var resolvedLink: String?

                    let fq = ["kotlin", "text", "isHighSurrogate"].map { interner.intern($0) }
                    let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == sema.types.charType
                            && signature.parameterTypes.isEmpty
                    })
                    resolvedLink = sema.symbols.externalLinkName(for: symbol)
                    #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isHighSurrogate() should return Boolean")

                #expect(sema.symbols.symbol(symbol)?.declSite != nil, "Char.isHighSurrogate() should be backed by Kotlin source")
                #expect(resolvedLink == nil, "Char.isHighSurrogate() should have no C external link")

            }

        }
    }

}

#endif
