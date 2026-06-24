#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropNativePlacementPlaceFunctionTests {
    @Test func testNativePlacementPlaceFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected NativePlacement.place<T>() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) })
            return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }

        let cVariableType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CVariable"),
            args: [],
            nullability: .nonNull
        )))
        let nativePlacementType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePlacement"),
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try cinteropSymbol("CValues")
        let cPointerSymbol = try cinteropSymbol("CPointer")

        let placeFQName = cinteropPkg + [interner.intern("place")]
        let placeSymbol = try #require(sema.symbols.lookupAll(fqName: placeFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nativePlacementType
                && signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 1
        }, "NativePlacement.place<T>(value: CValues<T>): CPointer<T> must be registered")

        let signature = try #require(sema.symbols.functionSignature(for: placeSymbol))
        let typeParameter = try #require(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedParamType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let flags = try #require(sema.symbols.symbol(placeSymbol)?.flags)

        #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        #expect(sema.symbols.parentSymbol(for: placeSymbol) == sema.symbols.lookup(fqName: cinteropPkg))
        #expect(signature.receiverType == nativePlacementType)
        #expect(signature.parameterTypes == [expectedParamType])
        #expect(signature.returnType == expectedReturnType)
        #expect(signature.typeParameterUpperBoundsList == [[cVariableType]])
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cVariableType])
        #expect(sema.symbols.parentSymbol(for: typeParameter) == placeSymbol)
        #expect(signature.reifiedTypeParameterIndices == [])
    }

    @Test func testNativePlacementPlaceFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.CVariable
        import kotlinx.cinterop.NativePlacement
        import kotlinx.cinterop.place

        fun <T : CVariable> copyValue(placement: NativePlacement, value: CValues<T>): CPointer<T> {
            return placement.place(value)
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected NativePlacement.place<T>(value: CValues<T>) to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
