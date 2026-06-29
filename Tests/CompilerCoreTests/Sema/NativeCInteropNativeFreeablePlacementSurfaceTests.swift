#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropNativeFreeablePlacementSurfaceTests {
    @Test func testNativeFreeablePlacementInterfaceSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected NativeFreeablePlacement surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            try #require(sema.symbols.lookup(fqName: (["kotlinx", "cinterop"] + path).map { interner.intern($0) }), "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }

        let nativeFreeablePlacementSymbol = try cinteropSymbol("NativeFreeablePlacement")
        let nativePlacementSymbol = try cinteropSymbol("NativePlacement")
        let nativeFreeablePlacementType = try cinteropType("NativeFreeablePlacement")

        #expect(sema.symbols.symbol(nativeFreeablePlacementSymbol)?.kind == .interface)
        #expect(sema.symbols.propertyType(for: nativeFreeablePlacementSymbol) == nativeFreeablePlacementType)
        #expect(sema.symbols.directSupertypes(for: nativeFreeablePlacementSymbol) == [nativePlacementSymbol])
        #expect(sema.types.directNominalSupertypes(for: nativeFreeablePlacementSymbol) == [nativePlacementSymbol])
    }

    @Test func testNativeFreeablePlacementResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.NativeFreeablePlacement
        import kotlinx.cinterop.NativePlacement

        fun upcast(value: NativeFreeablePlacement): NativePlacement {
            return value
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected NativeFreeablePlacement to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
