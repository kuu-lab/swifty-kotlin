#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-106: `fun String.toShort(): Short` in `kotlin.text`.
///
/// Verifies:
/// - `String.toShort` is source-backed after KSP-414 and no longer exposes a
///   public `kk_string_toShort` runtime link; it bridges through the private
///   `__kk_string_toShort` runtime symbol.
/// - The extension resolves cleanly from source code on both a parameter
///   receiver and a string-literal receiver (Short is widened to Int in ABI).
@Suite
struct StringToShortFunctionTests {
    @Test
    func testIntegerParsingOverloadsResolveWithExpectedTypes() throws {
        let source = """
        fun ubyte(raw: String): UByte = raw.toUByte()
        fun ubyteRadix(raw: String): UByte = raw.toUByte(radix = 16)
        fun ushort(raw: String): UShort = raw.toUShort()
        fun ushortRadix(raw: String): UShort = raw.toUShort(16)
        fun uint(raw: String): UInt = raw.toUInt()
        fun uintRadix(raw: String): UInt = raw.toUInt(16)
        fun ulong(raw: String): ULong = raw.toULong()
        fun ulongRadix(raw: String): ULong = raw.toULong(16)
        fun short(raw: String): Short = raw.toShort()
        fun shortRadix(raw: String): Short = raw.toShort(16)
        fun shortOrNull(raw: String): Short? = raw.toShortOrNull()
        fun shortOrNullRadix(raw: String): Short? = raw.toShortOrNull(radix = 16)
        fun byteOrNull(raw: String): Byte? = raw.toByteOrNull()
        fun byteOrNullRadix(raw: String): Byte? = raw.toByteOrNull(16)
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let members = [
            ("toUByte", sema.types.ubyteType),
            ("toUShort", sema.types.ushortType),
            ("toUInt", sema.types.uintType),
            ("toULong", sema.types.ulongType),
            ("toShort", sema.types.shortType),
            ("toShortOrNull", sema.types.makeNullable(sema.types.shortType)),
            ("toByteOrNull", sema.types.makeNullable(sema.types.byteType)),
        ]
        for (member, returnType) in members {
            let fq = ["kotlin", "text", member].map { ctx.interner.intern($0) }
            for arity in 0 ... 1 {
                let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbol in
                    guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
                    return signature.receiverType == sema.types.stringType
                        && signature.parameterTypes.count == arity
                }, "Missing String.\(member)/\(arity)")
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(signature.returnType == returnType)
                #expect(signature.parameterTypes == (arity == 0 ? [] : [sema.types.intType]))
                #expect(sema.symbols.externalLinkName(for: symbol) == nil)
            }
        }
    }

    @Test
    func testToShortResolvesInSource() throws {
        let source = """
        fun parse(raw: String): Short {
            return raw.toShort()
        }

        fun probe(): Int {
            return "1000".toShort().toInt()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let fq = ["kotlin", "text", "toShort"].map { interner.intern($0) }
        let allLinks = Set(sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(
            !allLinks.contains("kk_string_toShort") && !allLinks.contains("__kk_string_toShort"),
            "lookupAll for toShort must not include public or private string parse links; got: \(allLinks)"
        )

        let symbol = try #require(sema.symbols.lookup(fqName: fq))
        #expect(
            sema.symbols.externalLinkName(for: symbol) == nil,
            "String.toShort should be source-backed and have no C external link"
        )

        let bridgeFq = ["kotlin", "text", "__kk_string_toShort"].map { interner.intern($0) }
        #expect(
            sema.symbols.externalLinkName(for: try #require(sema.symbols.lookup(fqName: bridgeFq))) == "__kk_string_toShort",
            "Private __kk_string_toShort bridge should be registered"
        )
    }
}
#endif
