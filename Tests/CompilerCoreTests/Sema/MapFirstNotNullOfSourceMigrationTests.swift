#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct MapFirstNotNullOfSourceMigrationTests {
    @Test
    func testMapFirstNotNullOfFunctionsAreSourceBacked() throws {
        let source = """
        fun pick(values: Map<String?, Int?>): String {
            return values.firstNotNullOf<String> { entry ->
                if (entry.value != null) entry.key ?: "missing" else null
            }
        }

        fun pickOrNull(values: Map<String?, Int?>): String? {
            return values.firstNotNullOfOrNull<String> { entry ->
                if (entry.key == null) "null-key" else null
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, "Expected Map first-family calls to type-check: \(diagnosticSummary)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let packageFQName = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let mapFQName = packageFQName + [ctx.interner.intern("Map")]
            let entryFQName = mapFQName + [ctx.interner.intern("Entry")]

            func nominalOwnerFQName(for typeID: TypeID) -> [InternedString]? {
                switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
                case let .classType(classType):
                    return sema.symbols.symbol(classType.classSymbol)?.fqName
                default:
                    return nil
                }
            }

            for memberName in ["firstNotNullOf", "firstNotNullOfOrNull"] {
                let callID = try #require(
                    memberCallExprIDs(named: memberName, in: ast, interner: ctx.interner).first,
                    "Expected Map.\(memberName) call"
                )
                let chosen = try #require(
                    sema.bindings.callBinding(for: callID)?.chosenCallee,
                    "Expected chosen Map.\(memberName) callee"
                )
                let signature = try #require(sema.symbols.functionSignature(for: chosen))
                let receiverType = try #require(signature.receiverType)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(nominalOwnerFQName(for: receiverType) == mapFQName)
                #expect(!symbol.flags.contains(.synthetic))
                #expect(sema.symbols.isSourceBackedSymbol(chosen))
                #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            }

            let inputFileID = try #require(ctx.sourceManager.fileID(forPath: path))
            let entryPropertyCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      let range = ast.arena.exprRange(exprID),
                      range.start.file == inputFileID,
                      case let .memberCall(receiver, callee, _, _, _) = expr,
                      ["key", "value"].contains(ctx.interner.resolve(callee))
                else {
                    return nil
                }
                guard sema.bindings.exprType(for: receiver) != nil else {
                    return nil
                }
                return exprID
            }
            #expect(entryPropertyCalls.count == 3, "Expected Map.Entry key/value calls in both transforms")
            for callID in entryPropertyCalls {
                let binding = try #require(sema.bindings.callBinding(for: callID))
                let chosen = binding.chosenCallee
                let signature = try #require(sema.symbols.functionSignature(for: chosen))
                let receiverType = try #require(signature.receiverType)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(nominalOwnerFQName(for: receiverType) == entryFQName)
                #expect(sema.symbols.externalLinkName(for: chosen) == (symbol.name == ctx.interner.intern("key") ? "__kk_pair_first" : "__kk_pair_second"))
            }
        }
    }
}
#endif
