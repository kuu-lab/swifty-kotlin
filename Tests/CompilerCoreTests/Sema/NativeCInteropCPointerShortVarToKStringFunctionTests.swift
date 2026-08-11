#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerShortVarToKStringFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun noop() {}
        """,
        """
        package sample1
        fun noop() {}
        """,
        """
        package sample2
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.ShortVar
        import kotlinx.cinterop.toKString

        fun decode(p: CPointer<ShortVar>): String {
            return p.toKString()
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
    @Test func testCPointerShortVarToKStringFunctionSurfaceMatchesNativeShape() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "compile clean: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cPointerSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]))
        let shortVarSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("ShortVar")]))
        let shortVarType = sema.types.make(.classType(ClassType(classSymbol: shortVarSymbol, args: [], nullability: .nonNull)))
        let expectedReceiverType = sema.types.make(.classType(ClassType(classSymbol: cPointerSymbol, args: [.invariant(shortVarType)], nullability: .nonNull)))
        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKString")])
        let fn = try #require(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == expectedReceiverType && sig.parameterTypes.isEmpty && sig.returnType == sema.types.stringType
        })
        #expect(try #require(sema.symbols.symbol(fn)?.flags).contains(.synthetic))
    }

    @Test func testCPointerShortVarToKStringFunctionLinksToRuntimeSymbol() throws {

        let ctx = try sharedCtx()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cPointerSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]))
        let shortVarSymbol = try #require(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("ShortVar")]))
        let shortVarType = sema.types.make(.classType(ClassType(classSymbol: shortVarSymbol, args: [], nullability: .nonNull)))
        let expectedReceiverType = sema.types.make(.classType(ClassType(classSymbol: cPointerSymbol, args: [.invariant(shortVarType)], nullability: .nonNull)))
        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKString")])
        let fn = try #require(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == expectedReceiverType && sig.parameterTypes.isEmpty && sig.returnType == sema.types.stringType
        })
        #expect(sema.symbols.externalLinkName(for: fn) == "kk_cpointer_toKStringFromUtf16", "CPointer<ShortVar>.toKString() must link to kk_cpointer_toKStringFromUtf16")
    }

    @Test func testCPointerShortVarToKStringFunctionResolvesInSource() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
