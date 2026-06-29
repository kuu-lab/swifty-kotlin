#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropNativePlacementAllocArrayFunctionTests {
    @Test
    func testNativePlacementAllocArrayFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected NativePlacement.allocArray<T>(length) surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }
        func allocArraySignature(parameterType: TypeID) throws -> (SymbolID, FunctionSignature) {
            let functionFQName = cinteropPkg + [interner.intern("allocArray")]
            let nativePlacementType = try cinteropType("NativePlacement")
            let candidates = sema.symbols.lookupAll(fqName: functionFQName)
            let symbol = try #require(candidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nativePlacementType
                    && signature.parameterTypes == [parameterType]
                    && signature.typeParameterSymbols.count == 1
            })
            return (symbol, try #require(sema.symbols.functionSignature(for: symbol)))
        }
        func assertAllocArrayOverload(
            parameterType: TypeID
        ) throws {
            let cVariableType = try cinteropType("CVariable")
            let cPointerSymbol = try cinteropSymbol("CPointer")
            let (symbol, signature) = try allocArraySignature(parameterType: parameterType)
            let typeParameter = try #require(signature.typeParameterSymbols.first)
            let typeParameterType = sema.types.make(.typeParam(TypeParamType(
                symbol: typeParameter,
                nullability: .nonNull
            )))
            let expectedReturnType = sema.types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(typeParameterType)],
                nullability: .nonNull
            )))
            let flags = try #require(sema.symbols.symbol(symbol)?.flags)
            let typeParameterFlags = try #require(sema.symbols.symbol(typeParameter)?.flags)

            #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
            #expect(signature.returnType == expectedReturnType)
            #expect(signature.reifiedTypeParameterIndices == [0])
            #expect(signature.typeParameterUpperBoundsList == [[cVariableType]])
            #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cVariableType])
            #expect(
                typeParameterFlags.isSuperset(of: [.synthetic, .reifiedTypeParameter])
            )
            #expect(sema.symbols.parentSymbol(for: typeParameter) == symbol)
        }

        try assertAllocArrayOverload(parameterType: sema.types.longType)
        try assertAllocArrayOverload(parameterType: sema.types.intType)
    }

    @Test
    func testNativePlacementAllocArrayFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CArrayPointer
        import kotlinx.cinterop.NativePlacement
        import kotlinx.cinterop.allocArray

        fun allocateByteArrayLong(placement: NativePlacement): CArrayPointer<ByteVar> {
            return placement.allocArray<ByteVar>(4L)
        }

        fun allocateByteArrayInt(placement: NativePlacement): CArrayPointer<ByteVar> {
            return placement.allocArray<ByteVar>(4)
        }
        """)
        try runSema(ctx)

        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected NativePlacement.allocArray<ByteVar>(length) to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
