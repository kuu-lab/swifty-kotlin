#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-053: Validates that both overloads of `kotlin.text.removeSurrounding`
/// resolve through Sema for `String` receivers and dispatch to the correct runtime
/// link names:
///   - `removeSurrounding(delimiter)` → `kk_string_removeSurrounding`
///   - `removeSurrounding(prefix, suffix)` → `kk_string_removeSurrounding_pair`
///
/// Synthetic stubs are registered in `HeaderHelpers+SyntheticStringStubs.swift`.
/// Runtime implementations live in `RuntimeStringStdlib.swift`.
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

    // MARK: - Runtime link-name tests

    @Test func testRemoveSurroundingDelimiterResolvesToRuntimeLink() throws {
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
                    && signature.parameterTypes == [sema.types.stringType]
            })
            #expect(
                sema.symbols.externalLinkName(for: symbol) == "kk_string_removeSurrounding_flat",
                "Single-delimiter overload must map to kk_string_removeSurrounding_flat"
            )
            #expect(
                sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType,
                "String.removeSurrounding(delimiter) should return String"
            )
        }
    }

    @Test func testRemoveSurroundingPairResolvesToRuntimeLink() throws {
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
                    && signature.parameterTypes == [sema.types.stringType, sema.types.stringType]
            })
            #expect(
                sema.symbols.externalLinkName(for: symbol) == "kk_string_removeSurrounding_pair_flat",
                "Two-argument overload must map to kk_string_removeSurrounding_pair_flat"
            )
            #expect(
                sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType,
                "String.removeSurrounding(prefix, suffix) should return String"
            )
        }
    }
}
#endif
