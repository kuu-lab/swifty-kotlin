#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropListCPointerToCValuesFunctionTests {
    @Test func testListCPointerToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected List<CPointer<T>?>.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }

        let listSymbol = try #require(
            sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("List")]),
            "kotlin.collections.List must be registered"
        )
        let cValuesSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let cPointerSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]),
            "kotlinx.cinterop.CPointer must be registered"
        )
        let cPointerVarOfSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointerVarOf")]),
            "kotlinx.cinterop.CPointerVarOf must be registered"
        )
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try #require(
                sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointed")]),
                "kotlinx.cinterop.CPointed must be registered"
            ),
            args: [],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)

        let toCValues = try #require(
            toCValuesCandidates.first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                guard let typeParam = sig.typeParameterSymbols.first else { return false }
                let tParamType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParam,
                    nullability: .nonNull
                )))
                let nullableCPointerT = sema.types.make(.classType(ClassType(
                    classSymbol: cPointerSymbol,
                    args: [.invariant(tParamType)],
                    nullability: .nullable
                )))
                let expectedReceiver = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(nullableCPointerT)],
                    nullability: .nonNull
                )))
                return sig.receiverType == expectedReceiver && sig.parameterTypes.isEmpty
            },
            "No List<CPointer<T>?>.toCValues() overload found"
        )

        let signature = try #require(sema.symbols.functionSignature(for: toCValues))
        let typeParam = try #require(signature.typeParameterSymbols.first)
        let tParamType = sema.types.make(.typeParam(TypeParamType(symbol: typeParam, nullability: .nonNull)))

        let cPointerVarOfTType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(cPointerVarOfTType)],
            nullability: .nonNull
        )))
        #expect(signature.returnType == expectedReturnType)
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParam) == [cPointedType])
        #expect(signature.typeParameterUpperBoundsList == [[cPointedType]])

        let flags = try #require(sema.symbols.symbol(toCValues)?.flags)
        #expect(flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: toCValues) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test func testListCPointerToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.CPointerVarOf
        import kotlinx.cinterop.toCValues

        fun listToValues(ptrs: List<CPointer<ByteVar>?>): CValues<CPointerVarOf<ByteVar>> {
            return ptrs.toCValues()
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected List<CPointer<T>?>.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
