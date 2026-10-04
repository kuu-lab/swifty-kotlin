#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-1000: Iterator.iterator is a source-backed inline identity extension.
@Suite
struct IteratorIdentitySourceMigrationTests {
    @Test
    func iteratorIdentityExtensionIsSourceBackedInlineAndBound() throws {
        let source = """
        fun <T> identity(iterator: Iterator<T>): Iterator<T> =
            iterator.iterator()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected Iterator.iterator to type-check, got: \(errors)")
            )

            let sema = try #require(ctx.sema)
            let collections = ["kotlin", "collections"].map(ctx.interner.intern)
            let iteratorSymbol = try #require(
                sema.symbols.lookup(fqName: collections + [ctx.interner.intern("Iterator")])
            )
            let extensionFQName = collections + [ctx.interner.intern("iterator")]
            let sourceSymbols = sema.symbols.lookupAll(fqName: extensionFQName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/Iterators.kt"
            }

            #expect(sourceSymbols.count == 1, "Expected one bundled Iterator.iterator declaration")
            let extensionSymbol = try #require(sourceSymbols.first)
            let extensionInfo = try #require(sema.symbols.symbol(extensionSymbol))
            #expect(extensionInfo.flags.contains(.operatorFunction))
            #expect(extensionInfo.flags.contains(.inlineFunction))
            #expect(sema.symbols.isSourceBackedSymbol(extensionSymbol))
            #expect(sema.symbols.externalLinkName(for: extensionSymbol) == nil)

            let signature = try #require(sema.symbols.functionSignature(for: extensionSymbol))
            #expect(signature.parameterTypes.isEmpty)
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.classTypeParameterCount == 0)
            let receiverType = try #require(signature.receiverType)
            let returnType = signature.returnType
            guard case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  case let .classType(returnClass) = sema.types.kind(of: returnType)
            else {
                Issue.record("Iterator.iterator must use Iterator<T> for both receiver and return type")
                return
            }
            #expect(receiverClass.classSymbol == iteratorSymbol)
            #expect(returnClass.classSymbol == iteratorSymbol)
            #expect(receiverClass.args == returnClass.args)

            let ast = try #require(ctx.ast)
            let callID = try #require(
                ast.arena.exprs.indices.compactMap { index -> ExprID? in
                    let exprID = ExprID(rawValue: Int32(index))
                    guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID) else {
                        return nil
                    }
                    return ctx.interner.resolve(callee) == "iterator" ? exprID : nil
                }.last
            )
            let binding = try #require(sema.bindings.callBinding(for: callID))
            #expect(binding.chosenCallee == extensionSymbol)
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
        }
    }
}
#endif
