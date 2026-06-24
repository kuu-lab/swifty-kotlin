#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropMemScopedFunctionTests {
    @Test func testMemScopedFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected memScoped surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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

        let memScopeType = try cinteropType("MemScope")
        let memScopedFQName = cinteropPkg + [interner.intern("memScoped")]
        let memScopedSymbol = try #require(sema.symbols.lookupAll(fqName: memScopedFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try #require(sema.symbols.functionSignature(for: memScopedSymbol))
        let typeParameter = try #require(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedBlockType = sema.types.make(.functionType(FunctionType(
            receiver: memScopeType,
            params: [],
            returnType: typeParameterType
        )))
        let blockParameter = try #require(signature.valueParameterSymbols.first)
        let flags = try #require(sema.symbols.symbol(memScopedSymbol)?.flags)

        #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        #expect(signature.parameterTypes == [expectedBlockType])
        #expect(signature.returnType == typeParameterType)
        #expect(signature.typeParameterUpperBoundsList == [[]])
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("R"))
        #expect(sema.symbols.symbol(blockParameter)?.name == interner.intern("block"))
        #expect(sema.symbols.propertyType(for: blockParameter) == expectedBlockType)
        #expect(sema.symbols.parentSymbol(for: memScopedSymbol) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test func testMemScopedFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.memScoped

        fun scopedValue(): Int {
            return memScoped<Int> {
                42
            }
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected memScoped to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
