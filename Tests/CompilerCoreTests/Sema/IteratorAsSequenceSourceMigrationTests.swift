#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-631: Iterator.asSequence is a bundled Kotlin extension, not a legacy
/// runtime bridge. The call must resolve to the source-backed declaration.
@Suite
struct IteratorAsSequenceSourceMigrationTests {
    @Test
    func iteratorAsSequenceIsSourceBacked() throws {
        try withTemporaryFile(contents: """
        fun <T> convert(iterator: Iterator<T>): Sequence<T> = iterator.asSequence()
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected Iterator.asSequence to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
            )

            let sema = try #require(ctx.sema)
            let sourceFQName = ["kotlin", "sequences", "asSequence"].map(ctx.interner.intern)
            let sourceSymbols = sema.symbols.lookupAll(fqName: sourceFQName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/sequences/Sequences.kt"
            }

            #expect(sourceSymbols.count == 3, "Expected Iterable, Iterator, and Sequence asSequence source overloads")
            let iteratorTypeSymbol = sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Iterator"),
            ])
            let iteratorSymbols = sourceSymbols.filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      let receiverType = signature.receiverType,
                      let iteratorTypeSymbol
                else {
                    return false
                }
                guard case let .classType(classType) = sema.types.kind(of: receiverType) else {
                    return false
                }
                return classType.classSymbol == iteratorTypeSymbol
            }
            let iteratorAsSequenceSymbol = try #require(iteratorSymbols.first)
            #expect(sema.symbols.externalLinkName(for: iteratorAsSequenceSymbol) == nil)

            let ast = try #require(ctx.ast)
            let memberCallIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID) else {
                    return nil
                }
                return ctx.interner.resolve(callee) == "asSequence" ? exprID : nil
            }
            let callID = try #require(memberCallIDs.last)
            let binding = try #require(sema.bindings.callBinding(for: callID))
            #expect(binding.chosenCallee == iteratorAsSequenceSymbol)
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
        }
    }
}
#endif
