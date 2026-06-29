#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropArrayCPointerToCValuesFunctionTests {
    @Test func testArrayCPointerToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected Array<CPointer<T>?>.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        func cinteropSymbol(_ name: String) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: cinteropPkg + [interner.intern(name)])
            return try #require(found, "kotlinx.cinterop.\(name) must be registered")
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cValuesSymbol = try cinteropSymbol("CValues")
        let cPointerVarOfSymbol = try cinteropSymbol("CPointerVarOf")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointed"),
            args: [],
            nullability: .nonNull
        )))
        let kotlinArraySymbol = try #require(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("Array")]),
            "kotlin.Array must be registered"
        )

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)

        // Find the overload whose receiver is Array<CPointer<T>?> — uniquely identified by having a type parameter
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
                    classSymbol: kotlinArraySymbol,
                    args: [.invariant(nullableCPointerT)],
                    nullability: .nonNull
                )))
                return sig.receiverType == expectedReceiver
                    && sig.parameterTypes.isEmpty
                    && sig.typeParameterSymbols.count == 1
            },
            "Array<CPointer<T>?>.toCValues() must be registered"
        )

        let signature = try #require(sema.symbols.functionSignature(for: toCValues))
        let tParamSymbol = try #require(signature.typeParameterSymbols.first)
        let tParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))

        // Verify return type: CValues<CPointerVarOf<CPointer<T>>>
        let cPointerTNonNull = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let cPointerVarOfCPointerT = sema.types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(cPointerTNonNull)],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(cPointerVarOfCPointerT)],
            nullability: .nonNull
        )))
        #expect(signature.returnType == expectedReturnType)
        #expect(sema.symbols.typeParameterUpperBounds(for: tParamSymbol) == [cPointedType])
        #expect(signature.typeParameterUpperBoundsList == [[cPointedType]])

        let flags = try #require(sema.symbols.symbol(toCValues)?.flags)
        #expect(flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: toCValues) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test func testArrayCPointerToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toCValues

        fun usePtrs(ptrs: Array<CPointer<ByteVar>?>) {
            ptrs.toCValues()
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected Array<CPointer<T>?>.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
