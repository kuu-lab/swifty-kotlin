#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-009: Validates that `Char.isJavaIdentifierPart()` resolves through
/// Sema for plain Char receivers as well as literal contexts. The runtime link is
/// `kk_char_isJavaIdentifierPart` (see `Sources/Runtime/RuntimeChar.swift`).
@Suite
struct CharIsJavaIdentifierPartFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testCharIsJavaIdentifierPartResolvesInSource
            """
            package sample0

                    fun identifierPartCheck(ch: Char): Boolean {
                        return ch.isJavaIdentifierPart()
                    }

                    fun identifierPartLiteral(): Boolean {
                        return 'A'.isJavaIdentifierPart()
                    }

                    fun identifierPartDigit(): Boolean {
                        return '5'.isJavaIdentifierPart()
                    }

                    fun identifierPartUnderscore(): Boolean {
                        return '_'.isJavaIdentifierPart()
                    }

                    fun identifierPartIfBranch(ch: Char): Int {
                        return if (ch.isJavaIdentifierPart()) 1 else 0
                    }

            """,
            // testCharIsJavaIdentifierPartResolvesToRuntimeLink
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

            // === testCharIsJavaIdentifierPartResolvesInSource ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Char.isJavaIdentifierPart() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testCharIsJavaIdentifierPartResolvesToRuntimeLink ===

            do {




                var resolvedLink: String?

                    let fq = ["kotlin", "text", "isJavaIdentifierPart"].map { interner.intern($0) }
                    let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == sema.types.charType
                            && signature.parameterTypes.isEmpty
                    })
                    resolvedLink = sema.symbols.externalLinkName(for: symbol)
                    #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isJavaIdentifierPart() should return Boolean")

                #expect(resolvedLink == "kk_char_isJavaIdentifierPart")

            }

        }
    }

}

#endif
