#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-017: Validates that `Char.isUnicodeIdentifierPart` resolves
/// through Sema for plain Char receivers and literal contexts. The runtime link
/// involved is `kk_char_isUnicodeIdentifierPart`
/// (see `Sources/Runtime/RuntimeChar.swift`).
@Suite
struct CharIsUnicodeIdentifierPartFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testCharIsUnicodeIdentifierPartResolvesInSource
            """
            package sample0

                    fun identifierPartCheck(ch: Char): Boolean {
                        return ch.isUnicodeIdentifierPart()
                    }

                    fun identifierPartCheckLiteral(): Boolean {
                        return 'a'.isUnicodeIdentifierPart()
                    }

                    fun identifierPartCheckIfBranch(ch: Char): Int {
                        return if (ch.isUnicodeIdentifierPart()) 1 else 0
                    }

            """,
            // testCharIsUnicodeIdentifierPartResolvesToRuntimeLink
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

            // === testCharIsUnicodeIdentifierPartResolvesInSource ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Char.isUnicodeIdentifierPart() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testCharIsUnicodeIdentifierPartResolvesToRuntimeLink ===

            do {




                var resolvedLink: String?

                    let fq = ["kotlin", "text", "isUnicodeIdentifierPart"].map { interner.intern($0) }
                    let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == sema.types.charType
                            && signature.parameterTypes.isEmpty
                    })
                    resolvedLink = sema.symbols.externalLinkName(for: symbol)
                    #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isUnicodeIdentifierPart() should return Boolean")

                #expect(resolvedLink == "kk_char_isUnicodeIdentifierPart")

            }

        }
    }

}

#endif
