#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCArrayPointerVarTypeAliasTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun noop() {}
        """,
        """
        package sample1
        import kotlinx.cinterop.CArrayPointerVar
        import kotlinx.cinterop.CPointed

        fun pass(value: CArrayPointerVar<CPointed>): CArrayPointerVar<CPointed> {
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
    @Test func testCArrayPointerVarTypeAliasSurface() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "Expected CArrayPointerVar typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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

    @Test func testCArrayPointerVarResolvesInSource() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "Expected CArrayPointerVar typealias to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
