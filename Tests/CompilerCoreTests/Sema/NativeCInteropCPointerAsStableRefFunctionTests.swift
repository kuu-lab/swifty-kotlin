#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerAsStableRefFunctionTests {
    @Test func testCPointerAsStableRefFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected CPointer.asStableRef<T>() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let stableRefSymbol = try cinteropSymbol("StableRef")
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let asStableRefFQName = cinteropPkg + [interner.intern("asStableRef")]
        let asStableRef = try #require(sema.symbols.lookupAll(fqName: asStableRefFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try #require(sema.symbols.functionSignature(for: asStableRef))
        let typeParameter = try #require(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(typeParameterType)],
            nullability: .nonNull
        )))
        let flags = try #require(sema.symbols.symbol(asStableRef)?.flags)
        let typeParameterFlags = try #require(sema.symbols.symbol(typeParameter)?.flags)

        #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        #expect(sema.symbols.parentSymbol(for: asStableRef) == sema.symbols.lookup(fqName: cinteropPkg))
        #expect(signature.returnType == expectedReturnType)
        #expect(signature.reifiedTypeParameterIndices == [0])
        #expect(signature.typeParameterUpperBoundsList == [[sema.types.anyType]])
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [sema.types.anyType])
        #expect(typeParameterFlags.isSuperset(of: [.synthetic, .reifiedTypeParameter]))
        #expect(sema.symbols.parentSymbol(for: typeParameter) == asStableRef)
    }

    @Test func testCPointerAsStableRefFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.StableRef
        import kotlinx.cinterop.asStableRef

        fun restore(pointer: CPointer<*>): StableRef<String> {
            return pointer.asStableRef<String>()
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CPointer.asStableRef<String>() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
