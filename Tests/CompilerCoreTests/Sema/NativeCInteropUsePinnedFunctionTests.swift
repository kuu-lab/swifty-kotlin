#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropUsePinnedFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testUsePinnedFunctionSurfaceMatchesNativeShape
            """
            package sample0
            fun noop() {}
            """,
            // testUsePinnedFunctionResolvesInSource
            """
            package sample1

                    import kotlinx.cinterop.Pinned
                    import kotlinx.cinterop.usePinned

                    fun lengthOfPinned(value: String): Int {
                        return value.usePinned { pinned: Pinned<String> ->
                            pinned.get().length
                        }
                    }

            """,
            // testUsePinnedFunctionPropagatesReceiverToUnpin
            """
            package sample2

                    import kotlinx.cinterop.Pinned
                    import kotlinx.cinterop.usePinned

                    class Box(var value: Int)

                    fun readBoxed(box: Box): Int {
                        return box.usePinned { pinned: Pinned<Box> ->
                            val unwrapped = pinned.get()
                            unwrapped.value
                        }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testUsePinnedFunctionSurfaceMatchesNativeShape ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(!(
                    sample0Diagnostics.contains { $0.severity == .error }
                ), "Expected usePinned surface to compile cleanly, got: \(sample0Diagnostics)")
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

            // === testUsePinnedFunctionResolvesInSource ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(!(
                    sample1Diagnostics.contains { $0.severity == .error }
                ), "Expected usePinned to resolve, got: \(sample1Diagnostics)")

            }

            // === testUsePinnedFunctionPropagatesReceiverToUnpin ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                // Regression guard for the try/finally lowering shape (STDLIB-CINTEROP-FN-042):
                // the block result becomes the call result, and no error should be raised even
                // when the block itself contains control flow (a local val + expression body).
                #expect(!(
                    sample2Diagnostics.contains { $0.severity == .error }
                ), "Expected usePinned with a multi-statement block to resolve, got: \(sample2Diagnostics)")

            }

        }
    }

}

#endif
