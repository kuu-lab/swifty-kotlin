#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCOpaquePointerVarTypeAliasTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun noop() {}
        """,
        """
        package sample1
        import kotlinx.cinterop.COpaquePointerVar

        fun pass(value: COpaquePointerVar): COpaquePointerVar {
            return value
        }
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    @Test func testCOpaquePointerVarTypeAliasSurface() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "Expected COpaquePointerVar typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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

    @Test func testCOpaquePointerVarResolvesInSource() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "Expected COpaquePointerVar typealias to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
