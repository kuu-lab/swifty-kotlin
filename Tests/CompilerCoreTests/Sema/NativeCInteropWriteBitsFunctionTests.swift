#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropWriteBitsFunctionTests {
    @Test func testWriteBitsFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected writeBits surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let nativePtrSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("NativePtr")]),
            "kotlinx.cinterop.NativePtr must be registered"
        )
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: nativePtrSymbol,
            args: [],
            nullability: .nonNull
        )))

        let writeBitsFQName = cinteropPkg + [interner.intern("writeBits")]
        let writeBitsSymbol = try #require(
            sema.symbols.lookupAll(fqName: writeBitsFQName).first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == nil
                    && sig.parameterTypes.count == 4
                    && sig.parameterTypes[0] == nativePtrType
                    && sig.parameterTypes[1] == sema.types.longType
                    && sig.parameterTypes[2] == sema.types.intType
                    && sig.parameterTypes[3] == sema.types.longType
                    && sig.returnType == sema.types.unitType
            },
            "kotlinx.cinterop.writeBits(NativePtr, Long, Int, Long): Unit must be registered"
        )
        let flags = try #require(sema.symbols.symbol(writeBitsSymbol)?.flags)
        #expect(flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: writeBitsSymbol) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test func testWriteBitsFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.NativePtr
        import kotlinx.cinterop.writeBits

        fun writeOneBit(ptr: NativePtr) {
            writeBits(ptr, 0L, 1, 1L)
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected writeBits to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
