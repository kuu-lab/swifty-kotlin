#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-TYPE-005: Validates that `kotlin.text.Charsets` is registered
/// as a synthetic object in the `kotlin.text` package and exposes the expected
/// charset constants (UTF_8, UTF_16, US_ASCII, ISO_8859_1, UTF_16BE, UTF_16LE,
/// UTF_32, UTF_32BE, UTF_32LE), each with type `kotlin.text.Charset`.
/// See `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticStringStubs.swift`
/// for the registration site.
@Suite
struct CharsetsSyntheticObjectTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun noop() {}
        """,
        """
        package sample1
        import kotlin.text.Charsets
        import kotlin.text.Charset

        fun utf8(): Charset = Charsets.UTF_8
        fun iso88591(): Charset = Charsets.ISO_8859_1
        fun usAscii(): Charset = Charsets.US_ASCII
        fun utf16(): Charset = Charsets.UTF_16
        fun utf16be(): Charset = Charsets.UTF_16BE
        fun utf16le(): Charset = Charsets.UTF_16LE
        fun utf32(): Charset = Charsets.UTF_32
        fun utf32be(): Charset = Charsets.UTF_32BE
        fun utf32le(): Charset = Charsets.UTF_32LE

        fun encode(s: String) = s.toByteArray(Charsets.UTF_8)
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }

    private let charsetConstants = [
        "UTF_8", "ISO_8859_1", "US_ASCII",
        "UTF_16", "UTF_16BE", "UTF_16LE",
        "UTF_32", "UTF_32BE", "UTF_32LE",
    ]

    @Test func testCharsetsAndConstantsAreRegistered() throws {

        let ctx = try sharedCtx()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let objectFQ = ["kotlin", "text", "Charsets"].map { interner.intern($0) }
        let objectSymbol = try #require(
            sema.symbols.lookup(fqName: objectFQ),
            "Expected kotlin.text.Charsets to be registered as a synthetic object"
        )
        #expect(sema.symbols.symbol(objectSymbol)?.kind == .object)

        let classFQ = ["kotlin", "text", "Charset"].map { interner.intern($0) }
        let classSymbol = try #require(
            sema.symbols.lookup(fqName: classFQ),
            "Expected kotlin.text.Charset to be registered"
        )
        #expect(sema.symbols.symbol(classSymbol)?.kind == .class)

        let charsetType = sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))

        for name in charsetConstants {
            let fq = ["kotlin", "text", "Charsets", name].map { interner.intern($0) }
            let sym = try #require(
                sema.symbols.lookup(fqName: fq),
                "Expected Charsets.\(name) property to be registered"
            )
            let info = try #require(sema.symbols.symbol(sym))
            #expect(info.kind == .property, "Charsets.\(name) should be registered with kind=property")
            #expect(
                sema.symbols.propertyType(for: sym) == charsetType,
                "Charsets.\(name) should have type kotlin.text.Charset"
            )
        }
    }

    @Test func testCharsetsResolvesInSource() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Charsets constants and usage to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
