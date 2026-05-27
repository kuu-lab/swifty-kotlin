@testable import CompilerCore
import XCTest

final class NativeCInteropUnwrapKotlinObjectHolderFunctionTests: XCTestCase {
    func testUnwrapKotlinObjectHolderSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected unwrapKotlinObjectHolder<T>() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let unwrapFQName = cinteropPkg + [interner.intern("unwrapKotlinObjectHolder")]
        let candidates = sema.symbols.lookupAll(fqName: unwrapFQName)
        let unwrap = try XCTUnwrap(candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: unwrap))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(unwrap)?.flags)

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: unwrap), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(signature.returnType, typeParameterType)
        XCTAssertEqual(signature.reifiedTypeParameterIndices, [0])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[sema.types.anyType]])
    }

    func testUnwrapKotlinObjectHolderResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.COpaquePointer
        import kotlinx.cinterop.unwrapKotlinObjectHolder

        fun unwrapAny(holder: COpaquePointer?): String {
            return unwrapKotlinObjectHolder<String>(holder)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected unwrapKotlinObjectHolder<String>() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
