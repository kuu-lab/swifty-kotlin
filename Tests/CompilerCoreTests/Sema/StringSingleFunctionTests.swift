@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-066 / KSP-402: validates that String.single() resolves
/// through bundled Kotlin source across multiple call sites.
@Suite
struct StringSingleFunctionTests {
    @Test func testStringSingleResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun singleOf(s: String): Char {
            return s.single()
        }

        fun singleOfLiteral(): Char {
            return "x".single()
        }

        fun singleInBranch(s: String, take: Boolean): Char {
            return if (take) s.single() else "y".single()
        }

        fun callsBoth(s: String): Char {
            val a = s.single()
            val b = "z".single()
            return if (a == b) a else b
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.single() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSingleNoArgOverloadResolvesToBundledSource() throws {
        var resolvedLink: String?
        var resolvedReturnType: TypeID?
        var isSynthetic = false
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "single"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            isSynthetic = sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == true
            resolvedReturnType = sema.symbols.functionSignature(for: symbol)?.returnType
        }
        #expect(resolvedLink == nil)
        #expect(!isSynthetic)
        #expect(resolvedReturnType != nil, "single() should expose a return type")
    }

    @Test func testSingleOrNullCompanionResolvesToBundledSource() throws {
        // Sanity check that singleOrNull stays wired alongside single, since
        // they share the same kotlin.text source file.
        var resolvedLink: String?
        var isSynthetic = false
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "singleOrNull"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                    return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            isSynthetic = sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == true
        }
        #expect(resolvedLink == nil)
        #expect(!isSynthetic)
    }
}
