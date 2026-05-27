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

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) }),
                "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered"
            )
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointerVarOfSymbol = try cinteropSymbol("CPointerVarOf")
        let cPointedSymbol = try cinteropSymbol("CPointed")
        let cValuesSymbol = try cinteropSymbol("CValues")
        let arraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("Array")]),
            "kotlin.Array must be registered"
        )

        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: cPointedSymbol,
            args: [],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValues = try XCTUnwrap(sema.symbols.lookupAll(fqName: toCValuesFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID),
                  let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  receiverClass.classSymbol == arraySymbol,
                  signature.typeParameterSymbols.count == 1
            else {
                return false
            }
            return signature.parameterTypes.isEmpty
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toCValues))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))

        let expectedElementType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nullable
        )))
        let expectedReceiverType = sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(expectedElementType)],
            nullability: .nonNull
        )))
        let expectedNonNullPointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let expectedPointerVarType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(expectedNonNullPointerType)],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(expectedPointerVarType)],
            nullability: .nonNull
        )))

        let flags = try XCTUnwrap(sema.symbols.symbol(toCValues)?.flags)
        let typeParameterFlags = try XCTUnwrap(sema.symbols.symbol(typeParameter)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: toCValues), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(signature.receiverType, expectedReceiverType)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, expectedReturnType)
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cPointedType]])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cPointedType])
        XCTAssertTrue(typeParameterFlags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: typeParameter), toCValues)
    }

    func testArrayCPointerToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.CPointerVar
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.toCValues

        fun toPointers(arr: Array<CPointer<ByteVar>?>): CValues<CPointerVar<ByteVar>> {
            return arr.toCValues()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Array<CPointer<T>?>.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
