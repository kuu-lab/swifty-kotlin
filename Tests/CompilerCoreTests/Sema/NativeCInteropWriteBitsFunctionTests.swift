@testable import CompilerCore
import XCTest

final class NativeCInteropWriteBitsFunctionTests: XCTestCase {
    func testWriteBitsSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected writeBits() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let writeBitsFQName = cinteropPkg + [interner.intern("writeBits")]
        let candidates = sema.symbols.lookupAll(fqName: writeBitsFQName)
        let writeBits = try XCTUnwrap(candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 4
                && signature.typeParameterSymbols.isEmpty
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: writeBits))

        XCTAssertNil(signature.receiverType)
        XCTAssertEqual(signature.parameterTypes.count, 4)
        // offset: Long
        XCTAssertEqual(signature.parameterTypes[1], sema.types.longType)
        // size: Int
        XCTAssertEqual(signature.parameterTypes[2], sema.types.intType)
        // value: Long
        XCTAssertEqual(signature.parameterTypes[3], sema.types.longType)
        // returns Unit
        XCTAssertEqual(signature.returnType, sema.types.unitType)
        XCTAssertTrue(signature.typeParameterSymbols.isEmpty)
        XCTAssertTrue(signature.reifiedTypeParameterIndices.isEmpty)

        let flags = try XCTUnwrap(sema.symbols.symbol(writeBits)?.flags)
        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: writeBits), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testWriteBitsResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.COpaquePointer
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.writeBits

        @OptIn(ExperimentalForeignApi::class)
        fun test(ptr: COpaquePointer) {
            writeBits(ptr, 0L, 8, 0xFF.toLong())
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected writeBits() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
