@testable import CompilerCore
import XCTest

final class NativeCInteropArrayCPointerToCValuesFunctionTests: XCTestCase {
    func testArrayCPointerToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Array<CPointer<T>?>.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + [interner.intern(name)]),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cValuesSymbol = try cinteropSymbol("CValues")
        let cPointerVarOfSymbol = try cinteropSymbol("CPointerVarOf")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointed"),
            args: [],
            nullability: .nonNull
        )))
        let kotlinArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("Array")]),
            "kotlin.Array must be registered"
        )

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)

        // Find the overload whose receiver is Array<CPointer<T>?> — uniquely identified by having a type parameter
        let toCValues = try XCTUnwrap(
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

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toCValues))
        let tParamSymbol = try XCTUnwrap(signature.typeParameterSymbols.first)
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
        XCTAssertEqual(signature.returnType, expectedReturnType)
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: tParamSymbol), [cPointedType])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cPointedType]])

        let flags = try XCTUnwrap(sema.symbols.symbol(toCValues)?.flags)
        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: toCValues), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testArrayCPointerToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toCValues

        fun usePtrs(ptrs: Array<CPointer<ByteVar>?>) {
            ptrs.toCValues()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Array<CPointer<T>?>.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
