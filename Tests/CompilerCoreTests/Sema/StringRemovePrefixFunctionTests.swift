@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-050 / KSP-404: Validates that `String.removePrefix(prefix)` resolves
/// through Sema for `String` receivers across several invocation shapes (variable,
/// literal, chained call, and conditional contexts). The function is bundled Kotlin
/// source (`Stdlib/kotlin/text/StringPrefixSuffix.kt`) and therefore carries no
/// runtime external link.
@Suite
struct StringRemovePrefixFunctionTests {
    @Test func testRemovePrefixResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripScheme(s: String): String {
            return s.removePrefix("https://")
        }

        fun stripFromLiteral(): String {
            return "HelloWorld".removePrefix("Hello")
        }

        fun stripFromExpression(value: Int): String {
            return value.toString().removePrefix("0")
        }

        fun stripInBranch(s: String): String {
            return if (s.removePrefix("foo").isEmpty()) "empty" else s.removePrefix("foo")
        }

        fun stripChained(s: String): String {
            return s.removePrefix("a").removePrefix("b")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected removePrefix to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// Confirms the bundled `String.removePrefix(prefix)` source declaration is
    /// registered with a `String` receiver, returns `String`, and — being source
    /// backed after KSP-404 — carries no runtime external link.
    @Test func testRemovePrefixIsSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "removePrefix"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.returnType == sema.types.stringType
            })
            #expect(
                sema.symbols.externalLinkName(for: symbol) == nil,
                "String.removePrefix should be source-backed (no runtime link) after KSP-404"
            )
        }
    }
}
