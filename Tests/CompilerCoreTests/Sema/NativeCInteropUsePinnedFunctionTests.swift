#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropUsePinnedFunctionTests {
    @Test
    func testUsePinnedFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected usePinned surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            let found = sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) })
            return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
        }

        let pinnedSymbol = try cinteropSymbol(["Pinned"])
        let usePinnedSymbol = try cinteropSymbol(["usePinned"])
        let signature = try #require(sema.symbols.functionSignature(for: usePinnedSymbol))

        #expect(signature.typeParameterSymbols.count == 2)
        let tSymbol = try #require(signature.typeParameterSymbols.first)
        let rSymbol = try #require(signature.typeParameterSymbols.last)
        #expect(sema.symbols.symbol(tSymbol)?.name == interner.intern("T"))
        #expect(sema.symbols.symbol(rSymbol)?.name == interner.intern("R"))

        let tType = sema.types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
        let rType = sema.types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
        let expectedBlockParameterType = sema.types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(tType)],
            nullability: .nonNull
        )))
        let expectedBlockType = sema.types.make(.functionType(FunctionType(
            params: [expectedBlockParameterType],
            returnType: rType
        )))

        let flags = try #require(sema.symbols.symbol(usePinnedSymbol)?.flags)
        #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        #expect(signature.receiverType == tType)
        #expect(signature.parameterTypes == [expectedBlockType])
        #expect(signature.returnType == rType)
        #expect(signature.typeParameterUpperBoundsList == [[sema.types.anyType], []])
        #expect(sema.symbols.typeParameterUpperBounds(for: tSymbol) == [sema.types.anyType])
        #expect(sema.symbols.parentSymbol(for: usePinnedSymbol) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test
    func testUsePinnedFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.Pinned
        import kotlinx.cinterop.usePinned

        fun lengthOfPinned(value: String): Int {
            return value.usePinned { pinned: Pinned<String> ->
                pinned.get().length
            }
        }
        """)
        try runSema(ctx)

        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected usePinned to resolve, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func testUsePinnedFunctionPropagatesReceiverToUnpin() throws {
        // Regression guard for the try/finally lowering shape (STDLIB-CINTEROP-FN-042):
        // the block result becomes the call result, and no error should be raised even
        // when the block itself contains control flow (a local val + expression body).
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.Pinned
        import kotlinx.cinterop.usePinned

        class Box(var value: Int)

        fun readBoxed(box: Box): Int {
            return box.usePinned { pinned: Pinned<Box> ->
                val unwrapped = pinned.get()
                unwrapped.value
            }
        }
        """)
        try runSema(ctx)

        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected usePinned with a multi-statement block to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
