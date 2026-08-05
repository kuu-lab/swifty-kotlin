#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCOpaquePointerVarTypeAliasTests {
    @Test func testCOpaquePointerVar() throws {
        let source = """
        import kotlinx.cinterop.COpaquePointerVar

        fun pass(value: COpaquePointerVar): COpaquePointerVar {
            return value
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected COpaquePointerVar typealias to resolve, got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPackage = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let aliasSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("COpaquePointerVar")])
        )
        let cPointerVarOfSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CPointerVarOf")])
        )
        let cOpaquePointerAlias = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("COpaquePointer")])
        )
        let cOpaquePointerType = try #require(sema.symbols.typeAliasUnderlyingType(for: cOpaquePointerAlias))
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(cOpaquePointerType)],
            nullability: .nonNull
        )))
        #expect(sema.symbols.symbol(aliasSymbol)?.kind == .typeAlias)
        #expect(sema.symbols.typeAliasTypeParameters(for: aliasSymbol) == [])
        #expect(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol) == expectedUnderlying)
    }

}
#endif
