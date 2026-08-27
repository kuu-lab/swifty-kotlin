#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-912: The UShort(Short) constructor is a bundled source function over
/// the compiler's primitive UShort type.
@Suite
struct UShortSourceMigrationTests {
    @Test
    func ushortShortConstructorIsBundledSourceBacked() throws {
        let ctx = makeContextFromSource("""
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        fun construct(value: Short): UShort = UShort(value)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected UShort(Short) to type-check: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let candidates = sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("UShort"),
        ])
        let constructors = candidates.filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  let fileID = sema.symbols.sourceFileID(for: symbolID)
            else { return false }
            return signature.parameterTypes == [sema.types.shortType]
                && signature.returnType == sema.types.ushortType
                && symbol.visibility == .internal
                && !symbol.flags.contains(.synthetic)
                && sema.symbols.externalLinkName(for: symbolID) == nil
                && ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/UShort/Stdlib.kt"
        }

        #expect(constructors.count == 1, "Expected one bundled UShort(Short) constructor, found \(constructors)")
    }
}
#endif
