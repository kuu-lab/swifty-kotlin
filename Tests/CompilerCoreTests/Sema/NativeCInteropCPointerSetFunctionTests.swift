@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerSetFunctionTests: XCTestCase {
    func testCPointerSetFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.set surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + [interner.intern(name)]),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointed"),
            args: [],
            nullability: .nonNull
        )))

        let setFQName = cinteropPkg + [interner.intern("set")]
        let setFunction = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: setFQName).first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                guard let receiverTypeID = sig.receiverType else { return false }
                guard case let .classType(ct) = sema.types.kind(of: receiverTypeID) else { return false }
                return ct.classSymbol == cPointerSymbol
                    && sig.parameterTypes.count == 2
                    && sig.parameterTypes.first == sema.types.intType
                    && sig.returnType == sema.types.unitType
                    && sig.typeParameterSymbols.count == 1
            },
            "operator fun <T : CPointed> CPointer<T>.set(index: Int, value: T) must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: setFunction))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedReceiverType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(setFunction)?.flags)

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .operatorFunction]))
        XCTAssertEqual(signature.receiverType, expectedReceiverType)
        XCTAssertEqual(signature.parameterTypes, [sema.types.intType, typeParameterType])
        XCTAssertEqual(signature.returnType, sema.types.unitType)
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cPointedType]])
        XCTAssertEqual(signature.classTypeParameterCount, 0)
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cPointedType])
        XCTAssertEqual(sema.symbols.parentSymbol(for: typeParameter), setFunction)
    }

    func testCPointerSetFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.set

        fun <T : CPointed> store(ptr: CPointer<T>, index: Int, value: T) {
            ptr.set(index, value)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.set to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
