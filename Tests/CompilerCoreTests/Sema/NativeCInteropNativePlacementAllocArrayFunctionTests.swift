@testable import CompilerCore
import XCTest

final class NativeCInteropNativePlacementAllocArrayFunctionTests: XCTestCase {
    func testNativePlacementAllocArrayFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement.allocArray<T>(length) surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cVariableType = try cinteropType("CVariable")
        let nativePlacementType = try cinteropType("NativePlacement")
        let allocArrayFQName = cinteropPkg + [interner.intern("allocArray")]
        let allocArrayCandidates = sema.symbols.lookupAll(fqName: allocArrayFQName)

        func allocArray(lengthType: TypeID) throws -> (SymbolID, FunctionSignature) {
            let symbol = try XCTUnwrap(allocArrayCandidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nativePlacementType
                    && signature.parameterTypes == [lengthType]
                    && signature.typeParameterSymbols.count == 1
            })
            return (symbol, try XCTUnwrap(sema.symbols.functionSignature(for: symbol)))
        }

        let overloads = [
            try allocArray(lengthType: sema.types.intType),
            try allocArray(lengthType: sema.types.longType),
        ]

        for (symbol, signature) in overloads {
            let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
            let typeParameterType = sema.types.make(.typeParam(TypeParamType(
                symbol: typeParameter,
                nullability: .nonNull
            )))
            let expectedReturnType = sema.types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(typeParameterType)],
                nullability: .nonNull
            )))
            let flags = try XCTUnwrap(sema.symbols.symbol(symbol)?.flags)
            let typeParameterFlags = try XCTUnwrap(sema.symbols.symbol(typeParameter)?.flags)

            XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
            XCTAssertEqual(sema.symbols.parentSymbol(for: symbol), sema.symbols.lookup(fqName: cinteropPkg))
            XCTAssertEqual(signature.returnType, expectedReturnType)
            XCTAssertEqual(signature.reifiedTypeParameterIndices, [0])
            XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cVariableType]])
            XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cVariableType])
            XCTAssertTrue(typeParameterFlags.isSuperset(of: [.synthetic, .reifiedTypeParameter]))
            XCTAssertEqual(sema.symbols.parentSymbol(for: typeParameter), symbol)
        }
    }

    func testNativePlacementAllocArrayFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CArrayPointer
        import kotlinx.cinterop.NativePlacement
        import kotlinx.cinterop.allocArray

        fun allocateBytes(placement: NativePlacement): CArrayPointer<ByteVar> {
            return placement.allocArray<ByteVar>(4)
        }

        fun allocateBytesLong(placement: NativePlacement): CArrayPointer<ByteVar> {
            return placement.allocArray<ByteVar>(4L)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement.allocArray<ByteVar>(length) to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
