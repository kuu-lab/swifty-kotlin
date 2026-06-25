@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-TYPE-005: Validates that `kotlin.text.Charsets` is registered
/// as a synthetic object in the `kotlin.text` package and exposes the expected
/// charset constants (UTF_8, UTF_16, US_ASCII, ISO_8859_1, UTF_16BE, UTF_16LE,
/// UTF_32, UTF_32BE, UTF_32LE), each with type `kotlin.text.Charset`.
/// See `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticStringStubs.swift`
/// for the registration site.
final class CharsetsSyntheticObjectTests: XCTestCase {
    // MARK: - 1. Charsets object registration

    func testCharsetsIsRegisteredAsObjectInKotlinTextPackage() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "Charsets"].map { interner.intern($0) }
        let sym = try XCTUnwrap(
            sema.symbols.lookup(fqName: fq),
            "Expected kotlin.text.Charsets to be registered as a synthetic object"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(sym))
        XCTAssertEqual(info.kind, .object,
                       "Charsets should be registered with kind=object")
    }

    // MARK: - 2. Charset class registration

    func testCharsetClassIsRegisteredInKotlinTextPackage() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "Charset"].map { interner.intern($0) }
        let sym = try XCTUnwrap(
            sema.symbols.lookup(fqName: fq),
            "Expected kotlin.text.Charset to be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(sym))
        XCTAssertEqual(info.kind, .class,
                       "Charset should be registered with kind=class")
    }

    // MARK: - 3. Charset constant properties

    private let charsetConstants = [
        "UTF_8", "ISO_8859_1", "US_ASCII",
        "UTF_16", "UTF_16BE", "UTF_16LE",
        "UTF_32", "UTF_32BE", "UTF_32LE",
    ]

    func testCharsetsExposesAllExpectedConstantProperties() throws {
        let (sema, interner) = try makeSema()
        for name in charsetConstants {
            let fq = ["kotlin", "text", "Charsets", name].map { interner.intern($0) }
            let sym = try XCTUnwrap(
                sema.symbols.lookup(fqName: fq),
                "Expected Charsets.\(name) property to be registered"
            )
            let info = try XCTUnwrap(sema.symbols.symbol(sym))
            XCTAssertEqual(info.kind, .property,
                           "Charsets.\(name) should be registered with kind=property")
        }
    }

    func testCharsetsConstantPropertiesHaveCharsetType() throws {
        let (sema, interner) = try makeSema()
        let charsetFQ = ["kotlin", "text", "Charset"].map { interner.intern($0) }
        let charsetSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: charsetFQ))
        let charsetType = sema.types.make(.classType(ClassType(
            classSymbol: charsetSymbol,
            args: [],
            nullability: .nonNull
        )))

        for name in charsetConstants {
            let fq = ["kotlin", "text", "Charsets", name].map { interner.intern($0) }
            let sym = try XCTUnwrap(
                sema.symbols.lookup(fqName: fq),
                "Expected Charsets.\(name) to be registered"
            )
            let propType = sema.symbols.propertyType(for: sym)
            XCTAssertEqual(propType, charsetType,
                           "Charsets.\(name) should have type kotlin.text.Charset")
        }
    }

    // MARK: - 4. Source-level resolution

    func testCharsetsUTF8TypeChecksInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.text.Charsets

        fun getCharset() = Charsets.UTF_8
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Charsets.UTF_8 to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharsetsAllConstantsTypeCheckInSource() throws {
        let ctx = makeContextFromSource("""
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
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected all Charsets constants to type-check as kotlin.text.Charset, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharsetsUsedAsArgumentTypeChecks() throws {
        let ctx = makeContextFromSource("""
        import kotlin.text.Charsets

        fun encode(s: String) = s.toByteArray(Charsets.UTF_8)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Charsets.UTF_8 as argument to toByteArray to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
