#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DeepRecursiveSourceMigrationTests {
    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private static let sharedSources: [String] = [
        """
        fun noop() {}
        """,
        """
        class Node(val next: Node?)

        fun makeDepth(): DeepRecursiveFunction<Node?, Int> {
            val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> {
                if (it == null) 0 else callRecursive(it.next) + 1
            }
            return depth
        }

        fun useDepth(node: Node?): Int = makeDepth()(node)
        """,
    ]

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

    @Test func testDeepRecursiveAPISymbolsComeFromBundledKotlinSource() throws {
        let ctx = try sharedCtx()

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected bundled DeepRecursive.kt to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let functionFQName = ["kotlin", "DeepRecursiveFunction"].map(ctx.interner.intern)
        let scopeFQName = ["kotlin", "DeepRecursiveScope"].map(ctx.interner.intern)

        for fqName in [functionFQName, scopeFQName] {
            let classSymbol = try #require(sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .class
            })
            let info = try #require(sema.symbols.symbol(classSymbol))
            #expect(!info.flags.contains(.synthetic), "DeepRecursive types should be backed by bundled source")
            #expect(sema.types.nominalTypeParameterSymbols(for: classSymbol).count == 2)
            #expect(bundledSourcePath(for: classSymbol, sema: sema, ctx: ctx) == true)
        }

        let factorySymbol = try #require(sema.symbols.lookupAll(fqName: functionFQName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .function
        })
        #expect(sema.symbols.externalLinkName(for: factorySymbol) == "__kk_deep_recursive_function_new")
        #expect(bundledSourcePath(for: factorySymbol, sema: sema, ctx: ctx) == true)

        let invokeSymbol = try #require(member("invoke", of: functionFQName, sema: sema, ctx: ctx))
        #expect(sema.symbols.externalLinkName(for: invokeSymbol) == "__kk_deep_recursive_function_invoke")
        #expect(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)

        let functionCallRecursive = try #require(member("callRecursive", of: functionFQName, sema: sema, ctx: ctx))
        #expect(
            sema.symbols.externalLinkName(for: functionCallRecursive)
                == "__kk_deep_recursive_function_callRecursive"
        )

        let scopeCallRecursive = try #require(member("callRecursive", of: scopeFQName, sema: sema, ctx: ctx))
        #expect(
            sema.symbols.externalLinkName(for: scopeCallRecursive) == "__kk_deep_recursive_scope_callRecursive"
        )
    }

    @Test func testDeepRecursiveCallsResolveToBundledKotlinSourceSymbols() throws {
        let ctx = try sharedCtx()

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected DeepRecursive source calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let factoryCall = try #require(firstExprID(in: ast) { exprID, _ in
            guard let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee else { return false }
            return sema.symbols.externalLinkName(for: chosen) == "__kk_deep_recursive_function_new"
        })
        let factoryCallee = try #require(sema.bindings.callBinding(for: factoryCall)?.chosenCallee)
        #expect(bundledSourcePath(for: factoryCallee, sema: sema, ctx: ctx) == true)

        // `callRecursive(...)` inside the block resolves through ordinary
        // member lookup on the DeepRecursiveScope receiver, not a Sema special case.
        let callRecursiveCall = try #require(firstExprID(in: ast) { exprID, expr in
            guard case let .call(calleeID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeID),
                  case let .nameRef(name, _) = calleeExpr,
                  ctx.interner.resolve(name) == "callRecursive"
            else { return false }
            return sema.bindings.callBinding(for: exprID) != nil
        })
        let callRecursiveCallee = try #require(sema.bindings.callBinding(for: callRecursiveCall)?.chosenCallee)
        let calleeFQName = try #require(sema.symbols.symbol(callRecursiveCallee)?.fqName)
            .map { ctx.interner.resolve($0) }
            .joined(separator: ".")
        #expect(calleeFQName == "kotlin.DeepRecursiveScope.callRecursive")
        #expect(
            sema.symbols.externalLinkName(for: callRecursiveCallee) == "__kk_deep_recursive_scope_callRecursive"
        )
        #expect(bundledSourcePath(for: callRecursiveCallee, sema: sema, ctx: ctx) == true)
    }

    private func member(
        _ name: String,
        of ownerFQName: [InternedString],
        sema: SemaModule,
        ctx: CompilationContext
    ) -> SymbolID? {
        sema.symbols.lookupAll(fqName: ownerFQName + [ctx.interner.intern(name)]).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .function
        }
    }

    private func bundledSourcePath(
        for symbol: SymbolID,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> Bool {
        guard let fileID = sema.symbols.sourceFileID(for: symbol) else { return false }
        return ctx.sourceManager.path(of: fileID).contains("__bundled_kotlin/DeepRecursive.kt")
    }
}
#endif
