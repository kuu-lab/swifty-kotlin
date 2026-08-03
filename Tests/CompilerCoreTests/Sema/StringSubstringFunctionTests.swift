@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-073: Validates that `String.substring(startIndex[, endIndex])`
/// resolves through Sema for String receivers across multiple call sites. After
/// KSP-406 it is bundled Kotlin source (StringSubstringSlice.kt) with no
/// String-specific runtime helper, so the resolved symbol carries no external link.
@Suite
struct StringSubstringFunctionTests {
    @Test func testStringSubstringResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun headTwo(s: String): String {
            return s.substring(0, 2)
        }

        fun fromIndex(s: String): String {
            return s.substring(3)
        }

        fun substringOfLiteral(): String {
            return "hello world".substring(6, 11)
        }

        fun emptySliceOfLiteral(): String {
            return "abc".substring(1, 1)
        }

        fun substringInBranch(s: String, take: Boolean): String {
            return if (take) s.substring(0, 1) else s.substring(1)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.substring(...) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSubstringTwoArgOverloadIsSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "substring"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.count == 2
                    && signature.parameterTypes.allSatisfy { $0 == sema.types.intType }
            })
            #expect(
                sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType,
                "String.substring(startIndex, endIndex) should return String"
            )
            #expect(
                sema.symbols.externalLinkName(for: symbol) == nil,
                "String.substring(startIndex, endIndex) is source-backed and must not link to a runtime helper"
            )
        }
    }

    @Test func testSubstringOneArgOverloadIsSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "substring"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.count == 1
                    && signature.parameterTypes[0] == sema.types.intType
            })
            #expect(
                sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType,
                "String.substring(startIndex) should return String"
            )
            #expect(
                sema.symbols.externalLinkName(for: symbol) == nil,
                "String.substring(startIndex) is source-backed and must not link to a runtime helper"
            )
        }
    }
}
