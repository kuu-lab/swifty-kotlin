#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropNativeHeapPropertyTests {
    @Test func testNativeHeapPropertySurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected nativeHeap surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let nativeFreeablePlacementSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("NativeFreeablePlacement")]),
            "NativeFreeablePlacement must be registered"
        )
        let nativeFreeablePlacementType = sema.types.make(.classType(ClassType(
            classSymbol: nativeFreeablePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        let propertySymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("nativeHeap")]),
            "kotlinx.cinterop.nativeHeap must be registered"
        )

        #expect(sema.symbols.symbol(propertySymbol)?.kind == .property)
        #expect(sema.symbols.parentSymbol(for: propertySymbol) == sema.symbols.lookup(fqName: cinteropPkg))
        #expect(sema.symbols.propertyType(for: propertySymbol) == nativeFreeablePlacementType)
    }

    @Test func testNativeHeapPropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.NativeFreeablePlacement
        import kotlinx.cinterop.nativeHeap

        fun heap(): NativeFreeablePlacement {
            return nativeHeap
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected nativeHeap to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
