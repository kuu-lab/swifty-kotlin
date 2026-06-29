#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropNativePlacementAllocFunctionTests {
    @Test func testNativePlacementAllocFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected NativePlacement.alloc<T>() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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

        let cVariableType = try cinteropType("CVariable")
        let nativePlacementType = try cinteropType("NativePlacement")
        let allocFQName = cinteropPkg + [interner.intern("alloc")]
        let allocCandidates = sema.symbols.lookupAll(fqName: allocFQName)

        let alloc = try #require(allocCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nativePlacementType
                && signature.parameterTypes.isEmpty
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try #require(sema.symbols.functionSignature(for: alloc))
        let typeParameter = try #require(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let flags = try #require(sema.symbols.symbol(alloc)?.flags)
        let typeParameterFlags = try #require(sema.symbols.symbol(typeParameter)?.flags)

        #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        #expect(sema.symbols.parentSymbol(for: alloc) == sema.symbols.lookup(fqName: cinteropPkg))
        #expect(signature.returnType == typeParameterType)
        #expect(signature.reifiedTypeParameterIndices == [0])
        #expect(signature.typeParameterUpperBoundsList == [[cVariableType]])
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cVariableType])
        #expect(typeParameterFlags.isSuperset(of: [.synthetic, .reifiedTypeParameter]))
        #expect(sema.symbols.parentSymbol(for: typeParameter) == alloc)
    }

    @Test func testNativePlacementAllocFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.NativePlacement
        import kotlinx.cinterop.alloc

        fun allocateByte(placement: NativePlacement): ByteVar {
            return placement.alloc<ByteVar>()
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected NativePlacement.alloc<ByteVar>() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
