@testable import CompilerCore
import XCTest

final class NativeCInteropIntArrayToCValuesFunctionTests: XCTestCase {
    func testIntArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected IntArray.toCValues surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let intArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("IntArray")]),
            "kotlin.IntArray must be registered"
        )
        let intVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("IntVar")]),
            "kotlinx.cinterop.IntVar must be registered"
        )
        let cValuesSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: intArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let intVarType = sema.types.make(.classType(ClassType(
            classSymbol: intVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(intVarType)],
            nullability: .nonNull
        )))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toCValues")]).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == returnType
            },
            "IntArray.toCValues must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(sema.symbols.symbol(function)?.kind, .function)
        XCTAssertTrue(sema.symbols.symbol(function)?.flags.contains(.synthetic) == true)
        XCTAssertEqual(signature.receiverType, receiverType)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, returnType)
        XCTAssertEqual(signature.typeParameterSymbols, [])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [])
    }

    func testIntArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.IntVar
        import kotlinx.cinterop.toCValues

        fun convert(values: IntArray): CValues<IntVar> {
            return values.toCValues()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected IntArray.toCValues to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
