#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCArrayPointerTypeAliasTests {
    @Test func testCArrayPointerTypeAliasSurface() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected CArrayPointer typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPackage = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let aliasSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CArrayPointer")])
        )
        let cPointerSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CPointer")])
        )
        let typeParameter = try #require(sema.symbols.typeAliasTypeParameters(for: aliasSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        #expect(sema.symbols.symbol(aliasSymbol)?.kind == .typeAlias)
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("T"))
        #expect(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol) == expectedUnderlying)
    }

    @Test func testCArrayPointerResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CArrayPointer
        import kotlinx.cinterop.CPointed

        fun pass(value: CArrayPointer<CPointed>): CArrayPointer<CPointed> {
            return value
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CArrayPointer typealias to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
