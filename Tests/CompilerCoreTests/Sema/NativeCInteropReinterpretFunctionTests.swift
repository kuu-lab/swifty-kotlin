#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropReinterpretFunctionTests {
    @Test func testReinterpretFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected CPointer<*>.reinterpret<T>() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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

        let cPointedType = try cinteropType("CPointed")
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointerStarType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let reinterpretFQName = cinteropPkg + [interner.intern("reinterpret")]
        let reinterpretCandidates = sema.symbols.lookupAll(fqName: reinterpretFQName)

        let reinterpret = try #require(reinterpretCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == cPointerStarType
                && signature.parameterTypes.isEmpty
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try #require(sema.symbols.functionSignature(for: reinterpret))
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
        let flags = try #require(sema.symbols.symbol(reinterpret)?.flags)
        let typeParameterFlags = try #require(sema.symbols.symbol(typeParameter)?.flags)

        #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        #expect(sema.symbols.parentSymbol(for: reinterpret) == sema.symbols.lookup(fqName: cinteropPkg))
        #expect(signature.returnType == expectedReturnType)
        #expect(signature.reifiedTypeParameterIndices == [0])
        #expect(signature.typeParameterUpperBoundsList == [[cPointedType]])
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cPointedType])
        #expect(typeParameterFlags.isSuperset(of: [.synthetic, .reifiedTypeParameter]))
        #expect(sema.symbols.parentSymbol(for: typeParameter) == reinterpret)
    }

    @Test func testReinterpretFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.IntVar
        import kotlinx.cinterop.reinterpret

        fun reinterpretPointer(rawPointer: CPointer<ByteVar>): CPointer<IntVar> {
            return rawPointer.reinterpret<IntVar>()
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CPointer<ByteVar>.reinterpret<IntVar>() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
