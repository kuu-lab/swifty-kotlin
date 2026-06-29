#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCOpaquePointerTypeAliasTests {
    @Test func testCOpaquePointerTypeAliasSurface() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected COpaquePointer typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPackage = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let aliasSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("COpaquePointer")])
        )
        let cPointerSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CPointer")])
        )
        let cPointedSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CPointed")])
        )
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: cPointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.out(cPointedType)],
            nullability: .nonNull
        )))

        #expect(sema.symbols.symbol(aliasSymbol)?.kind == .typeAlias)
        #expect(sema.symbols.typeAliasTypeParameters(for: aliasSymbol) == [])
        #expect(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol) == expectedUnderlying)
    }

    @Test func testCOpaquePointerResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.COpaquePointer

        fun pass(value: COpaquePointer): COpaquePointer {
            return value
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected COpaquePointer typealias to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
