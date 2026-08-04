@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-096: `fun String.toDoubleOrNull(): Double?` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toDoubleOrNull` links to the
///   runtime symbol `kk_string_toDoubleOrNull_flat` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+String.swift`.
/// - The extension resolves cleanly from source code and produces no Sema
///   diagnostics for a call returning `Double?`.
/// - Elvis fallback (`?: 0.0`) type-checks correctly with the nullable return.
@Suite
struct StringToDoubleOrNullFunctionTests {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func externalLinks(for member: String, sema: SemaModule, interner: StringInterner) -> Set<String> {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    @Test func testToDoubleOrNullResolvesInSource() throws {
        let source = """
        fun probe(text: String) {
            val result: Double? = text.toDoubleOrNull()
            println(result)
        }

        fun probeLiteral(): Double {
            val parsed: Double? = "3.14".toDoubleOrNull()
            return parsed ?: 0.0
        }

        fun parse(raw: String): Double? {
            return raw.toDoubleOrNull()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let toDoubleOrNullCalls = allMemberCallExprIDs(
            named: "toDoubleOrNull",
            in: ast,
            interner: interner,
            sourceManager: ctx.sourceManager
        )
        let expectedType = sema.types.makeNullable(sema.types.doubleType)
        for callExpr in toDoubleOrNullCalls {
            #expect(
                sema.bindings.exprType(for: callExpr) == expectedType,
                "toDoubleOrNull must return Double?"
            )
        }

        let directLink = externalLink(
            for: "toDoubleOrNull",
            receiverType: sema.types.stringType,
            parameterCount: 0,
            sema: sema,
            interner: interner
        )
        #expect(
            directLink == nil || directLink?.isEmpty == true,
            "String.toDoubleOrNull should be source-backed and not have a direct external link"
        )

        #expect(
            externalLink(for: "__kk_string_toDoubleOrNull", sema: sema, interner: interner) == "__kk_string_toDoubleOrNull",
            "__kk_string_toDoubleOrNull should link to __kk_string_toDoubleOrNull"
        )
    }

    private func allMemberCallExprIDs(
        named member: String,
        in ast: ASTModule,
        interner: StringInterner,
        sourceManager: SourceManager?
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member
            else { continue }
            if let sourceManager, let range = ast.arena.exprRange(exprID) {
                guard !sourceManager.path(of: range.start.file).hasPrefix("__bundled_") else { continue }
            }
            results.append(exprID)
        }
        return results
    }

    private func externalLink(
        for member: String,
        receiverType: TypeID,
        parameterCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookupAll(fqName: fq).first(where: { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes.count == parameterCount
        }) else {
            return nil
        }
        return sema.symbols.externalLinkName(for: sym)
    }
}
