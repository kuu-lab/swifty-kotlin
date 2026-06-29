#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-PROP-020: Validates that `kotlin.text.lowercase` resolves through
/// Sema as a `Char` extension (Kotlin spec defines it as
/// `fun Char.lowercase(): String`). The runtime link name involved is
/// `kk_char_lowercase`. A locale overload (`fun Char.lowercase(locale: Locale): String`)
/// also resolves and links to `kk_char_lowercase_locale`.
@Suite
struct CharLowercaseFunctionTests {
    @Test func testLowercaseResolvesOnCharLiteralReceiver() throws {
        let ctx = makeContextFromSource("""
        fun lowercaseOfLiteral(): String {
            return 'A'.lowercase()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected lowercase to type-check on a Char literal, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testLowercaseResolvesOnCharParameterReceiver() throws {
        let ctx = makeContextFromSource("""
        fun toLower(ch: Char): String {
            return ch.lowercase()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected lowercase to type-check on a Char parameter, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testLowercaseLinksToCorrectRuntimeSymbol() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let fq = ["kotlin", "text", "lowercase"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == sema.types.charType
                && signature.parameterTypes.isEmpty
        }, "Char.lowercase() must be registered as a synthetic extension function")
        #expect(sema.symbols.externalLinkName(for: symbol) == "kk_char_lowercase")

        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        #expect(signature.returnType == sema.types.stringType, "Char.lowercase() should return String per Kotlin spec")
    }

    @Test func testLowercaseWithLocaleResolvesAndLinksToLocaleRuntimeSymbol() throws {
        let ctx = makeContextFromSource("""
        import java.util.Locale

        fun toLowerWithLocale(ch: Char, loc: Locale): String {
            return ch.lowercase(loc)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected lowercase(Locale) to type-check on a Char parameter, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let fq = ["kotlin", "text", "lowercase"].map { interner.intern($0) }
        let localeOverload = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == sema.types.charType
                && signature.parameterTypes.count == 1
        }, "Char.lowercase(Locale) overload must be registered")
        #expect(sema.symbols.externalLinkName(for: localeOverload) == "kk_char_lowercase_locale")
    }
}
#endif
