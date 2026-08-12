#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCOpaquePointerTypeAliasTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun noop() {}
        """,
        """
        package sample1
        import kotlinx.cinterop.COpaquePointer

        fun pass(value: COpaquePointer): COpaquePointer {
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
    @Test func testCOpaquePointerTypeAliasSurface() throws {

        let ctx = try sharedCtx()
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

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "Expected COpaquePointer typealias to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
