#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-008: Validates that `Char.isIdentifierIgnorable()` resolves
/// through Sema for plain Char receivers as well as literal and branch contexts.
/// The runtime link involved is `kk_char_isIdentifierIgnorable` (see
/// `Sources/Runtime/RuntimeChar.swift`).
@Suite
struct CharIsIdentifierIgnorableFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testCharIsIdentifierIgnorableResolvesInSource
            """
            package sample0

                    fun ignorableCheck(ch: Char): Boolean {
                        return ch.isIdentifierIgnorable()
                    }

                    fun ignorableCheckLiteral(): Boolean {
                        return '\\u0001'.isIdentifierIgnorable()
                    }

                    fun ignorableCheckIfBranch(ch: Char): Int {
                        return if (ch.isIdentifierIgnorable()) 1 else 0
                    }

            """,
            // testCharIsIdentifierIgnorableResolvesToRuntimeLink
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

            // === testCharIsIdentifierIgnorableResolvesInSource ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Char.isIdentifierIgnorable() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testCharIsIdentifierIgnorableResolvesToRuntimeLink ===

            do {




                var resolvedLink: String?

                    let fq = ["kotlin", "text", "isIdentifierIgnorable"].map { interner.intern($0) }
                    let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == sema.types.charType
                            && signature.parameterTypes.isEmpty
                    })
                    resolvedLink = sema.symbols.externalLinkName(for: symbol)
                    #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isIdentifierIgnorable() should return Boolean")

                #expect(resolvedLink == "kk_char_isIdentifierIgnorable")

            }

        }
    }

}

#endif
