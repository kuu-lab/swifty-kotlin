#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-084: `fun String.toBigDecimalOrNull(): BigDecimal?` in `kotlin.text`.
@Suite
struct StringToBigDecimalOrNullFunctionTests {
    private func allMemberCallExprIDs(
        named member: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member
            else { continue }
            results.append(exprID)
        }
        return results
    }

    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func bigDecimalType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let fq = ["java", "math", "BigDecimal"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fq))
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    @Test func testToBigDecimalOrNullResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.math.BigDecimal

        fun probe(text: String) {
            val result: BigDecimal? = text.toBigDecimalOrNull()
            println(result)
        }

        fun parse(raw: String): BigDecimal {
            return raw.toBigDecimalOrNull() ?: "0".toBigDecimal()
        }
        """)

        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.isEmpty,
            "Expected String.toBigDecimalOrNull() to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let expectedType = sema.types.makeNullable(try bigDecimalType(sema: sema, interner: interner))
        let callIDs = allMemberCallExprIDs(named: "toBigDecimalOrNull", in: ast, interner: interner)
        #expect(callIDs.count == 2, "Expected two toBigDecimalOrNull calls")
        for callID in callIDs {
            #expect(sema.bindings.exprType(for: callID) == expectedType)
        }

        let directLink = externalLink(for: "toBigDecimalOrNull", sema: sema, interner: interner)
        #expect(
            directLink == nil || directLink?.isEmpty == true,
            "String.toBigDecimalOrNull should be source-backed and not have a direct external link"
        )
        #expect(
            externalLink(for: "__kk_string_toBigDecimalOrNull", sema: sema, interner: interner)
                == "__kk_string_toBigDecimalOrNull",
            "__kk_string_toBigDecimalOrNull should link to __kk_string_toBigDecimalOrNull"
        )
    }
}
#endif
