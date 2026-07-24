#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-053 / KSP-404: Validates that both overloads of
/// `kotlin.text.removeSurrounding` resolve through Sema for `String` receivers.
/// Both overloads are bundled Kotlin source
/// (`Stdlib/kotlin/text/StringPrefixSuffix.kt`) and carry no runtime external link.
@Suite
struct StringRemoveSurroundingFunctionTests {
    // MARK: - Type-check tests

    @Test func testRemoveSurroundingDelimiterResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripBrackets(s: String): String {
            return s.removeSurrounding("[")
        }

        fun stripTripleAsterisk(): String {
            return "***star***".removeSurrounding("***")
        }

        fun stripExactMatch(): String {
            return "ab".removeSurrounding("ab")
        }

        fun stripNoMatch(): String {
            return "abc".removeSurrounding("ab")
        }

        fun stripChained(s: String): String {
            return s.removeSurrounding("(").removeSurrounding(")")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected removeSurrounding(delimiter) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testRemoveSurroundingPairResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripDiv(s: String): String {
            return s.removeSurrounding("<div>", "</div>")
        }

        fun stripBracketItem(): String {
            return "[item]".removeSurrounding("[", "]")
        }

        fun stripNoMatch(): String {
            return "no-match".removeSurrounding("<", ">")
        }

        fun stripFromExpression(value: Int): String {
            return value.toString().removeSurrounding("(", ")")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected removeSurrounding(prefix, suffix) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Source-backed (no runtime link) tests

    @Test func testRemoveSurroundingDelimiterIsSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "removeSurrounding"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.count == 1
                    && signature.returnType == sema.types.stringType
            })
            #expect(
                sema.symbols.externalLinkName(for: symbol) == nil,
                "String.removeSurrounding(delimiter) should be source-backed after KSP-404"
            )
        }
    }

    @Test func testRemoveSurroundingPairIsSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "removeSurrounding"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.count == 2
                    && signature.returnType == sema.types.stringType
            })
            #expect(
                sema.symbols.externalLinkName(for: symbol) == nil,
                "String.removeSurrounding(prefix, suffix) should be source-backed after KSP-404"
            )
        }
    }
}
#endif
