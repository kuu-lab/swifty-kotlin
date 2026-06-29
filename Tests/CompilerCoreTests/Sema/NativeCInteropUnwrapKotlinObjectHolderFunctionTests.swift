#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropUnwrapKotlinObjectHolderFunctionTests {
    @Test func testUnwrapKotlinObjectHolderSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected unwrapKotlinObjectHolder<T>() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let unwrapFQName = cinteropPkg + [interner.intern("unwrapKotlinObjectHolder")]
        let candidates = sema.symbols.lookupAll(fqName: unwrapFQName)
        let unwrap = try #require(candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try #require(sema.symbols.functionSignature(for: unwrap))
        let typeParameter = try #require(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let flags = try #require(sema.symbols.symbol(unwrap)?.flags)

        #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        #expect(sema.symbols.parentSymbol(for: unwrap) == sema.symbols.lookup(fqName: cinteropPkg))
        #expect(signature.returnType == typeParameterType)
        #expect(signature.reifiedTypeParameterIndices == [0])
        #expect(signature.typeParameterUpperBoundsList == [[sema.types.anyType]])
    }

    @Test func testUnwrapKotlinObjectHolderResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.COpaquePointer
        import kotlinx.cinterop.unwrapKotlinObjectHolder

        fun unwrapAny(holder: COpaquePointer?): String {
            return unwrapKotlinObjectHolder<String>(holder)
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected unwrapKotlinObjectHolder<String>() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
