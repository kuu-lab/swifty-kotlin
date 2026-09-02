#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IterableTakeSourceMigrationTests {
    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }

    @Test
    func migratedIterableTakeFunctionsAreBundledSourceDefinitions() throws {
        let ctx = try sharedCtx()
        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)
        let expectedArities: [String: Int] = ["take": 1, "takeWhile": 1]

        for (name, arity) in expectedArities {
            let fqName = packageFQName + [ctx.interner.intern(name)]
            let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/Iterables.kt"
            }

            let matchingSymbols = sourceSymbols.filter {
                sema.symbols.functionSignature(for: $0)?.parameterTypes.count == arity
            }
            #expect(matchingSymbols.count == 1, "Expected one bundled Iterable.(name) declaration")
            let symbol = try #require(matchingSymbols.first)
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.receiverType != nil, "Iterable.(name) must be an extension function")
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
            #expect(sema.symbols.isSourceBackedSymbol(symbol))
            if name == "takeWhile" {
                #expect(sema.symbols.symbol(symbol)?.flags.contains(.inlineFunction) == true)
            } else {
                #expect(sema.symbols.symbol(symbol)?.flags.contains(.inlineFunction) == false)
            }
        }
    }

    @Test
    func iterableTakeCallsBindToIterableFQNameAfterReceiverUpcast() throws {
        let source = """
        fun probe(values: Iterable<Int>) {
            values.take(2)
            values.takeWhile { it > 0 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected Iterable take-family calls to type-check")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedFQNames = ["take", "takeWhile"].map {
                packageFQName(ctx, name: $0)
            }
            var chosenFQNames: [[InternedString]] = []

            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ["take", "takeWhile"].contains(ctx.interner.resolve(callee)),
                      let binding = sema.bindings.callBinding(for: exprID),
                      let symbol = sema.symbols.symbol(binding.chosenCallee)
                else {
                    continue
                }
                chosenFQNames.append(symbol.fqName)
                #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
                #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
            }

            #expect(chosenFQNames.contains(expectedFQNames[0]))
            #expect(chosenFQNames.contains(expectedFQNames[1]))
        }
    }

    private func packageFQName(_ ctx: CompilationContext, name: String) -> [InternedString] {
        ["kotlin", "collections", name].map(ctx.interner.intern)
    }
}
#endif
