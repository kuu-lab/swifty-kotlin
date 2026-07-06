#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCEnumVarSurfaceTests {
    @Test
    func testCEnumVarClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected CEnumVar surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) })
            return try requireTestValue(found, "kotlinx.cinterop.\(name) must be registered")
        }

        let cEnumVarSymbol = try cinteropSymbol("CEnumVar")
        let cEnumVarType = sema.types.make(.classType(ClassType(
            classSymbol: cEnumVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePtr"),
            args: [],
            nullability: .nonNull
        )))

        #expect(sema.symbols.symbol(cEnumVarSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(cEnumVarSymbol)?.flags.contains(.abstractType) == true)
        #expect(sema.symbols.propertyType(for: cEnumVarSymbol) == cEnumVarType)
        #expect(sema.symbols.directSupertypes(for: cEnumVarSymbol) == [try cinteropSymbol("CPrimitiveVar")])
        #expect(sema.types.directNominalSupertypes(for: cEnumVarSymbol) == [try cinteropSymbol("CPrimitiveVar")])

        let fqName = try #require(sema.symbols.symbol(cEnumVarSymbol)?.fqName)
        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cEnumVarType
        })
        #expect(constructorSignature.valueParameterHasDefaultValues == [false])
    }

    @Test
    func testCEnumVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CEnumVar

        fun pass(value: CEnumVar): CEnumVar {
            return value
        }
        """)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.hasError),
            "Expected CEnumVar to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
