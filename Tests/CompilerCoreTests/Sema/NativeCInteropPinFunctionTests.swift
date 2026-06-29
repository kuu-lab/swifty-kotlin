#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropPinFunctionTests {
    @Test
    func testPinFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected pin surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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

        let pinnedSymbol = try cinteropSymbol("Pinned")
        let pinnedTypeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: pinnedSymbol).first)
        let pinnedTypeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: pinnedTypeParameter,
            nullability: .nonNull
        )))
        let pinnedType = sema.types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(pinnedTypeParameterType)],
            nullability: .nonNull
        )))

        #expect(sema.symbols.symbol(pinnedSymbol)?.kind == .class)
        #expect(sema.symbols.propertyType(for: pinnedSymbol) == pinnedType)
        #expect(sema.symbols.symbol(pinnedTypeParameter)?.name == interner.intern("T"))
        #expect(sema.symbols.typeParameterUpperBounds(for: pinnedTypeParameter) == [sema.types.anyType])
        #expect(sema.types.nominalTypeParameterVariances(for: pinnedSymbol) == [.invariant])

        let pinFQName = cinteropPkg + [interner.intern("pin")]
        let pinSymbol = try #require(sema.symbols.lookupAll(fqName: pinFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes.isEmpty
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try #require(sema.symbols.functionSignature(for: pinSymbol))
        let typeParameter = try #require(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let flags = try #require(sema.symbols.symbol(pinSymbol)?.flags)

        #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        #expect(signature.receiverType == typeParameterType)
        #expect(signature.returnType == expectedReturnType)
        #expect(signature.typeParameterUpperBoundsList == [[sema.types.anyType]])
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [sema.types.anyType])
        #expect(sema.symbols.parentSymbol(for: pinSymbol) == sema.symbols.lookup(fqName: cinteropPkg))
    }

    @Test
    func testPinFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.Pinned
        import kotlinx.cinterop.pin

        fun pinString(value: String): Pinned<String> {
            return value.pin()
        }
        """)
        try runSema(ctx)

        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected pin to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
