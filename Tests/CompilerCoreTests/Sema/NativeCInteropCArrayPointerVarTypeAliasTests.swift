#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCArrayPointerVarTypeAliasTests {
    @Test func testCArrayPointerVar() throws {
        let source = """
        import kotlinx.cinterop.CArrayPointerVar
        import kotlinx.cinterop.CPointed

        fun pass(value: CArrayPointerVar<CPointed>): CArrayPointerVar<CPointed> {
            return value
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CArrayPointerVar typealias to resolve, got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPackage = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let aliasSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CArrayPointerVar")])
        )
        let cPointerVarSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CPointerVar")])
        )
        let typeParameter = try #require(sema.symbols.typeAliasTypeParameters(for: aliasSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: cPointerVarSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        #expect(sema.symbols.symbol(aliasSymbol)?.kind == .typeAlias)
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("T"))
        #expect(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol) == expectedUnderlying)
    }

}
#endif
