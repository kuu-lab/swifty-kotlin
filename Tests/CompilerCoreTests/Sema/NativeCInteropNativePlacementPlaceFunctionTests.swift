@testable import CompilerCore
import XCTest

final class NativeCInteropNativePlacementPlaceFunctionTests: XCTestCase {
    func testNativePlacementPlaceFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement.place<T>() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) }),
                "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered"
            )
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }

        let cVariableType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CVariable"),
            args: [],
            nullability: .nonNull
        )))
        let nativePlacementType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePlacement"),
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try cinteropSymbol("CValues")
        let cPointerSymbol = try cinteropSymbol("CPointer")

        let placeFQName = cinteropPkg + [interner.intern("place")]
        let placeSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: placeFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nativePlacementType
                && signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 1
        }, "NativePlacement.place<T>(value: CValues<T>): CPointer<T> must be registered")

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: placeSymbol))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedParamType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(placeSymbol)?.flags)

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: placeSymbol), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(signature.receiverType, nativePlacementType)
        XCTAssertEqual(signature.parameterTypes, [expectedParamType])
        XCTAssertEqual(signature.returnType, expectedReturnType)
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cVariableType]])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cVariableType])
        XCTAssertEqual(sema.symbols.parentSymbol(for: typeParameter), placeSymbol)
        XCTAssertEqual(signature.reifiedTypeParameterIndices, [])
    }

    func testNativePlacementPlaceFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.CVariable
        import kotlinx.cinterop.NativePlacement
        import kotlinx.cinterop.place

        fun <T : CVariable> copyValue(placement: NativePlacement, value: CValues<T>): CPointer<T> {
            return placement.place(value)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement.place<T>(value: CValues<T>) to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
