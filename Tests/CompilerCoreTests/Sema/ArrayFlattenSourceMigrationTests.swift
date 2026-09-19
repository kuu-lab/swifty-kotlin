#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KUU-541: Array flatten is backed by bundled source extensions — the
/// upstream `Array<out Array<out T>>` overload plus the KSwiftK-only
/// `Array<out Iterable<T>>` superset — and must coexist with the
/// List/Iterable/Sequence overloads.
@Suite
struct ArrayFlattenSourceMigrationTests {
    @Test
    func arrayFlattenResolvesToBundledSourceOverloads() throws {
        let source = """
        fun probeArrays(values: Array<Array<Int>>): List<Int> = values.flatten()
        fun probeIterables(values: Array<List<Int>>): List<Int> = values.flatten()
        fun probeSets(values: Array<Set<Int>>): List<Int> = values.flatten()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(callee) == "flatten"
                else {
                    return nil
                }
                return exprID
            }
            #expect(callExprIDs.count == 3, "Expected Array<Array>, Array<List>, and Array<Set> flatten calls")

            for callExprID in callExprIDs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExprID)?.chosenCallee,
                    "Expected a Sema binding for flatten"
                )
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                let fileID = try #require(sema.symbols.sourceFileID(for: chosenCallee))
                #expect(
                    ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/Arrays.kt",
                    "flatten should resolve to the bundled Arrays.kt overloads"
                )

                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let receiverType = sema.types.makeNonNullable(try #require(signature.receiverType))
                guard case let .classType(receiverClass) = sema.types.kind(of: receiverType) else {
                    Issue.record("Expected flatten receiver to be a class type")
                    continue
                }
                #expect(
                    sema.symbols.symbol(receiverClass.classSymbol)?.fqName.map(ctx.interner.resolve)
                        == ["kotlin", "Array"]
                )

                let resultType = try #require(sema.bindings.exprType(for: callExprID))
                guard case let .classType(resultClass) = sema.types.kind(of: sema.types.makeNonNullable(resultType)) else {
                    Issue.record("Expected flatten to return a List")
                    continue
                }
                #expect(
                    sema.symbols.symbol(resultClass.classSymbol)?.fqName.map(ctx.interner.resolve)
                        == ["kotlin", "collections", "List"]
                )
            }

            let flattenFQName = ["kotlin", "collections", "flatten"].map(ctx.interner.intern)
            let arraySourceSymbols = sema.symbols.lookupAll(fqName: flattenFQName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID),
                      ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/Arrays.kt",
                      let receiverType = sema.symbols.functionSignature(for: symbolID)?.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    return false
                }
                return receiverSymbol.fqName.map(ctx.interner.resolve) == ["kotlin", "Array"]
            }
            #expect(arraySourceSymbols.count == 2)
            #expect(arraySourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        }
    }
}
#endif
