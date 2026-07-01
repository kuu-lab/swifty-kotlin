#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCValueUseContentsFunctionTests {
    @Test
    func testUseContentsFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected useContents surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            let found = sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) })
            return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
        }

        let cValueSymbol = try cinteropSymbol("CValue")
        let cStructVarSymbol = try cinteropSymbol("CStructVar")
        let useContentsSymbol = try cinteropSymbol("useContents")
        let signature = try #require(sema.symbols.functionSignature(for: useContentsSymbol))

        #expect(signature.typeParameterSymbols.count == 2)
        let tSymbol = try #require(signature.typeParameterSymbols.first)
        let rSymbol = try #require(signature.typeParameterSymbols.last)
        #expect(sema.symbols.symbol(tSymbol)?.name == interner.intern("T"))
        #expect(sema.symbols.symbol(rSymbol)?.name == interner.intern("R"))

        let tType = sema.types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
        let rType = sema.types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
        let cStructVarType = sema.types.make(.classType(ClassType(
            classSymbol: cStructVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValueOfT = sema.types.make(.classType(ClassType(
            classSymbol: cValueSymbol,
            args: [.invariant(tType)],
            nullability: .nonNull
        )))
        let expectedBlockType = sema.types.make(.functionType(FunctionType(
            receiver: tType,
            params: [],
            returnType: rType
        )))

        let flags = try #require(sema.symbols.symbol(useContentsSymbol)?.flags)
        #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        #expect(signature.receiverType == cValueOfT)
        #expect(signature.parameterTypes == [expectedBlockType])
        #expect(signature.returnType == rType)
        #expect(signature.typeParameterUpperBoundsList == [[cStructVarType], []])
        #expect(sema.symbols.typeParameterUpperBounds(for: tSymbol) == [cStructVarType])
        #expect(sema.symbols.parentSymbol(for: useContentsSymbol) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test
    func testUseContentsFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CStructVar
        import kotlinx.cinterop.CValue
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.useContents

        @ExperimentalForeignApi
        fun <T : CStructVar> expose(value: CValue<T>): T {
            return value.useContents { this }
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CValue.useContents to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
