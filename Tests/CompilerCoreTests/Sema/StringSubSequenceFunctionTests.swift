#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-072: Validates that `String.subSequence(startIndex, endIndex)`
/// resolves through Sema for String receivers and links to the runtime helper
/// `kk_string_subSequence` (see `Sources/Runtime/RuntimeStringStdlib.swift`).
/// Note: `subSequence` is deprecated in favour of `substring(startIndex, endIndex)`.
@Suite
struct StringSubSequenceFunctionTests {
    @Test func testStringSubSequenceResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        @Suppress("KSWIFTK-SEMA-DEPRECATED")
        fun headTwo(s: String): String {
            return s.subSequence(0, 2)
        }

        @Suppress("KSWIFTK-SEMA-DEPRECATED")
        fun tailThree(s: String): String {
            return s.subSequence(s.length - 3, s.length)
        }

        @Suppress("KSWIFTK-SEMA-DEPRECATED")
        fun emptySlice(s: String): String {
            return s.subSequence(1, 1)
        }

        @Suppress("KSWIFTK-SEMA-DEPRECATED")
        fun subSequenceOfLiteral(): String {
            return "hello world".subSequence(6, 11)
        }

        @Suppress("KSWIFTK-SEMA-DEPRECATED")
        fun subSequenceInBranch(s: String, take: Boolean): String {
            return if (take) s.subSequence(0, 1) else s.subSequence(1, 2)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.subSequence(...) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSubSequenceTwoArgOverloadResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "subSequence"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.count == 2
                    && signature.parameterTypes.allSatisfy { $0 == sema.types.intType }
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            #expect(
                sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType,
                "String.subSequence(startIndex, endIndex) should return String"
            )
        }
        #expect(resolvedLink == "kk_string_subSequence_flat")
    }
}
#endif
