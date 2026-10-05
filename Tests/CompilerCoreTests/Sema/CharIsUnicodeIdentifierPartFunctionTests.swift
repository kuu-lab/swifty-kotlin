#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-1252: Unicode identifier predicates are Java static methods, not Kotlin Char APIs.
@Suite
struct CharIsUnicodeIdentifierPartFunctionTests {
    @Test(arguments: [
        "fun probe(ch: Char): Boolean = ch.isUnicodeIdentifierPart()",
        "fun main() { println('1'.isUnicodeIdentifierPart()) }",
        "fun probe(ch: Char): Boolean = ch.isUnicodeIdentifierStart()",
        "fun main() { println('a'.isUnicodeIdentifierStart()) }",
    ])
    func unicodeIdentifierPredicatesAreUnresolved(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.code == "KSWIFTK-SEMA-0024")
    }

    @Test
    func unicodeIdentifierPredicatesAreNotRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)

        for name in ["isUnicodeIdentifierPart", "isUnicodeIdentifierStart"] {
            let fqName = ["kotlin", "text", name].map { ctx.interner.intern($0) }
            #expect(sema.symbols.lookupAll(fqName: fqName).isEmpty)
        }
    }

    @Test
    func userDefinedUnicodeIdentifierExtensionStillResolves() throws {
        let ctx = makeContextFromSource("""
        fun Char.isUnicodeIdentifierPart(): Boolean = this == '1'
        fun main() { println('1'.isUnicodeIdentifierPart()) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
    }
}
#endif
