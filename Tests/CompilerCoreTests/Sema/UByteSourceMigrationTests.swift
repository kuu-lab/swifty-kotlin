#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-903: The UByte(Byte) constructor is represented by a bundled Kotlin
/// source function over the compiler's primitive UByte type.
@Suite
struct UByteSourceMigrationTests {
    @Test
    func ubyteByteConstructorIsBundledSourceBacked() throws {
        let ctx = makeContextFromSource("""
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        fun construct(value: Byte): UByte = UByte(value)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected UByte(Byte) to type-check: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let candidates = sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("UByte"),
        ])
        let constructors = candidates.filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  let fileID = sema.symbols.sourceFileID(for: symbolID)
            else { return false }
            return signature.parameterTypes == [sema.types.byteType]
                && signature.returnType == sema.types.ubyteType
                && symbol.visibility == .internal
                && !symbol.flags.contains(.synthetic)
                && sema.symbols.externalLinkName(for: symbolID) == nil
                && ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/ubyte.kt"
        }

        #expect(constructors.count == 1, "Expected one bundled UByte(Byte) constructor, found \(constructors)")
    }

    /// KSP-1534: `UByte` has no `toChar()` member in real Kotlin. See the
    /// matching `UShortSourceMigrationTests.ushortToCharIsUnresolved` for the
    /// shared root cause (Subtyping.swift misclassified `.ubyte`/`.ushort`
    /// as `<: Number`).
    @Test
    func ubyteToCharIsUnresolved() throws {
        let ctx = makeContextFromSource("""
        fun convert(value: UByte): Char = value.toChar()
        """)
        try runSema(ctx)
        let unresolved = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0024" }
        #expect(
            !unresolved.isEmpty,
            "Expected UByte.toChar() to be unresolved, matching kotlinc: \(ctx.diagnostics.diagnostics)"
        )
    }

    /// KSP-1534 root cause: `UByte` must not satisfy a `Number` upper
    /// bound. kotlinc rejects `val n: Number = someUByte` outright.
    @Test
    func ubyteIsNotSubtypeOfNumber() throws {
        let ctx = makeContextFromSource("""
        fun convert(value: UByte): Number = value
        """)
        try runSema(ctx)
        let typeErrors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-TYPE-0001" }
        #expect(
            !typeErrors.isEmpty,
            "Expected UByte to not satisfy a Number upper bound: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
