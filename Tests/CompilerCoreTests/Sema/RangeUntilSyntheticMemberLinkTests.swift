#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct RangeUntilSyntheticMemberLinkTests {
    private func untilSymbols(for sema: SemaModule, interner: StringInterner) -> [SymbolID] {
        sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern("until"),
        ])
    }

    private func untilCallExprIDs(
        in ast: ASTModule,
        interner: StringInterner,
        sourceManager: SourceManager
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == "until",
                  // Exclude bundled stdlib source (e.g. kotlin.random.Random's own
                  // `until` usage) so this only counts calls from the test's own
                  // fixture, regardless of how the stdlib itself uses `until`.
                  let range = ast.arena.exprRange(exprID),
                  !sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            else {
                return nil
            }
            return exprID
        }
    }

    @Test func testUntilOverloadsAndCalls() throws {
        let source = """
        fun sample(b: Byte, s: Short, i: Int, l: Long) {
            val byteRange = b until b
            val shortRange = s until s
            val intRange = i until i
            val intLongRange = i until l
            val longIntRange = l until i
            val longRange = l until l
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let interner = ctx.interner
        let sema = try #require(ctx.sema)
        let untilSymbolIDs = untilSymbols(for: sema, interner: interner)

        // Byte and Short collapse to intType internally; mixed Int/Long calls widen to Long.
        let expectedSignatures: [(receiver: TypeID, parameter: TypeID, returnType: TypeID, link: String)] = [
            (sema.types.intType, sema.types.intType, sema.types.intType, "kk_op_rangeUntil"),
            (sema.types.intType, sema.types.longType, sema.types.longType, "kk_op_rangeUntil"),
            (sema.types.longType, sema.types.intType, sema.types.longType, "kk_op_rangeUntil"),
            (sema.types.longType, sema.types.longType, sema.types.longType, "kk_op_rangeUntil"),
        ]

        for entry in expectedSignatures {
            let matchingSymbol = untilSymbolIDs.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == entry.receiver
                    && signature.parameterTypes == [entry.parameter]
                    && signature.returnType == entry.returnType
            }
            let symbol = try #require(matchingSymbol, Comment(rawValue: "Expected until stub for \(entry.receiver)"))
            #expect(
                sema.symbols.externalLinkName(for: symbol) == entry.link,
                Comment(rawValue: "Expected \(entry.receiver).until to link to \(entry.link)")
            )
        }

        let ast = try #require(ctx.ast)
        let untilCalls = untilCallExprIDs(in: ast, interner: interner, sourceManager: ctx.sourceManager)

        #expect(untilCalls.count == 6)

        let expectedCalls: [(type: TypeID, link: String, isUIntRange: Bool, isULongRange: Bool)] = [
            (sema.types.intType, "kk_op_rangeUntil", false, false),
            (sema.types.intType, "kk_op_rangeUntil", false, false),
            (sema.types.intType, "kk_op_rangeUntil", false, false),
            (sema.types.longType, "kk_op_rangeUntil", false, false),
            (sema.types.longType, "kk_op_rangeUntil", false, false),
            (sema.types.longType, "kk_op_rangeUntil", false, false),
        ]

        for (exprID, entry) in zip(untilCalls, expectedCalls) {
            let binding = try #require(sema.bindings.callBinding(for: exprID))
            let chosen = binding.chosenCallee
            #expect(
                sema.symbols.externalLinkName(for: chosen) == entry.link,
                Comment(rawValue: "Expected until call to resolve to \(entry.link)")
            )
            #expect(
                sema.bindings.exprType(for: exprID) == entry.type,
                "Unexpected inferred type for until call"
            )
            #expect(sema.bindings.isRangeExpr(exprID), "until should mark a range expression")
            #expect(
                sema.bindings.isUIntRangeExpr(exprID) == entry.isUIntRange,
                "Unexpected UInt range marker for until call"
            )
            #expect(
                sema.bindings.isULongRangeExpr(exprID) == entry.isULongRange,
                "Unexpected ULong range marker for until call"
            )
        }
    }
}
#endif
