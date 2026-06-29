#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropNativeFreeablePlacementFreeFunctionTests {
    @Test func testNativeFreeablePlacementFreePointedFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected NativeFreeablePlacement.free(pointed) surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) })
            return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
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

        let nativeFreeablePlacementType = try cinteropType("NativeFreeablePlacement")
        let nativePointedType = try cinteropType("NativePointed")
        let freeFQName = cinteropPkg + [interner.intern("free")]
        let freeSymbol = try #require(sema.symbols.lookupAll(fqName: freeFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nativeFreeablePlacementType
                && signature.parameterTypes == [nativePointedType]
                && signature.returnType == sema.types.unitType
        })
        let signature = try #require(sema.symbols.functionSignature(for: freeSymbol))
        let parameterSymbol = try #require(signature.valueParameterSymbols.first)
        let flags = try #require(sema.symbols.symbol(freeSymbol)?.flags)

        #expect(flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: freeSymbol) == sema.symbols.lookup(fqName: cinteropPkg))
        #expect(signature.valueParameterHasDefaultValues == [false])
        #expect(signature.valueParameterIsVararg == [false])
        #expect(sema.symbols.symbol(parameterSymbol)?.name == interner.intern("pointed"))
        #expect(sema.symbols.propertyType(for: parameterSymbol) == nativePointedType)
    }

    @Test func testNativeFreeablePlacementFreePointedFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.NativeFreeablePlacement
        import kotlinx.cinterop.NativePointed
        import kotlinx.cinterop.free

        fun release(placement: NativeFreeablePlacement, pointed: NativePointed) {
            placement.free(pointed)
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected NativeFreeablePlacement.free(pointed) to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
