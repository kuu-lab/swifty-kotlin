#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-004: Validates that `Char.isDefined()` resolves through
/// Sema for plain Char receivers as well as literal and branch contexts. The
/// runtime link involved is `kk_char_isDefined` (see
/// `Sources/Runtime/RuntimeChar.swift`).
@Suite
struct CharIsDefinedFunctionTests {
    @Test func testCharIsDefinedResolvesInSource() throws {
        let ctx = makeContextFromSource("""
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
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isDefined() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testCharIsDefinedResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "isDefined"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isDefined() should return Boolean")
        }
        #expect(resolvedLink == "kk_char_isDefined")
    }
}
#endif
