#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCOpaqueSurfaceTests {
    @Test
    func testCOpaqueClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected COpaque surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) })
            return try requireTestValue(found, "kotlinx.cinterop.\(name) must be registered")
        }

        let cOpaqueSymbol = try cinteropSymbol("COpaque")
        let cOpaqueType = sema.types.make(.classType(ClassType(
            classSymbol: cOpaqueSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePtr"),
            args: [],
            nullability: .nonNull
        )))

        #expect(sema.symbols.symbol(cOpaqueSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(cOpaqueSymbol)?.flags.contains(.abstractType) == true)
        #expect(sema.symbols.propertyType(for: cOpaqueSymbol) == cOpaqueType)
        #expect(sema.symbols.directSupertypes(for: cOpaqueSymbol) == [try cinteropSymbol("CPointed")])
        #expect(sema.types.directNominalSupertypes(for: cOpaqueSymbol) == [try cinteropSymbol("CPointed")])

        let fqName = try #require(sema.symbols.symbol(cOpaqueSymbol)?.fqName)
        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cOpaqueType
        })
        #expect(constructorSignature.valueParameterHasDefaultValues == [false])
    }

    @Test
    func testCOpaqueResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.COpaque

        fun pass(value: COpaque): COpaque {
            return value
        }
        """)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.hasError),
            "Expected COpaque to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
