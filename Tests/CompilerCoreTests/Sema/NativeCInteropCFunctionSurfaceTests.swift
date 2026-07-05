#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCFunctionSurfaceTests {
    @Test
    func testCFunctionClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected CFunction surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) })
            return try requireTestValue(found, "kotlinx.cinterop.\(name) must be registered")
        }

        let cFunctionSymbol = try cinteropSymbol("CFunction")
        let typeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: cFunctionSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let cFunctionType = sema.types.make(.classType(ClassType(
            classSymbol: cFunctionSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePtr"),
            args: [],
            nullability: .nonNull
        )))

        #expect(sema.symbols.symbol(cFunctionSymbol)?.kind == .class)
        #expect(sema.types.nominalTypeParameterVariances(for: cFunctionSymbol) == [.invariant])
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("T"))
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [sema.types.anyType])
        #expect(sema.symbols.propertyType(for: cFunctionSymbol) == cFunctionType)
        #expect(sema.symbols.directSupertypes(for: cFunctionSymbol) == [try cinteropSymbol("CPointed")])
        #expect(sema.types.directNominalSupertypes(for: cFunctionSymbol) == [try cinteropSymbol("CPointed")])

        let fqName = try #require(sema.symbols.symbol(cFunctionSymbol)?.fqName)
        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cFunctionType
        })
        #expect(constructorSignature.typeParameterSymbols == [typeParameter])
        #expect(constructorSignature.classTypeParameterCount == 1)
        #expect(constructorSignature.valueParameterHasDefaultValues == [false])
    }

    @Test
    func testCFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CFunction

        fun pass(value: CFunction<() -> Int>): CFunction<() -> Int> {
            return value
        }
        """)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.hasError),
            "Expected CFunction to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
