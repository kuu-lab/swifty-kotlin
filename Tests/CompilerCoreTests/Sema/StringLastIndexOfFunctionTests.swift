@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-034: Validates that `CharSequence.lastIndexOf` resolves through
/// Sema for the (Char, startIndex, ignoreCase) overload and gets wired to the
/// runtime entry point `kk_string_lastIndexOf_char_flat`. The previously-existing
/// String/String overloads remain wired to `kk_string_lastIndexOf_flat` and
/// `kk_string_lastIndexOf_ignoreCase_flat` respectively.
@Suite
struct StringLastIndexOfFunctionTests {
    private struct MemberCallInfo {
        let exprID: ExprID
        let args: [CallArgument]
    }

    private func allMemberCallInfos(
        named member: String,
        in ast: ASTModule,
        interner: StringInterner,
        sourceManager: SourceManager?
    ) -> [MemberCallInfo] {
        var results: [MemberCallInfo] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, args, _) = expr,
                  interner.resolve(callee) == member
            else { continue }
            if let sourceManager, let range = ast.arena.exprRange(exprID) {
                guard !sourceManager.path(of: range.start.file).hasPrefix("__bundled_") else { continue }
            }
            results.append(MemberCallInfo(exprID: exprID, args: args))
        }
        return results
    }

    @Test func testLastIndexOfResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun String.findDelimiter(delimiter: String): Int {
            return indexOf(delimiter)
        }

        fun lastChar(value: String): Int {
            return value.lastIndexOf('l')
        }

        fun findChar(value: CharSequence): Int {
            return value.lastIndexOf('o', 10, false)
        }

        fun findCharIgnoreCase(value: String): Int {
            return value.lastIndexOf('O', 10, true)
        }

        fun probe(value: CharSequence): Int {
            return value.lastIndexOf('x', 0, false)
        }

        fun lastCharWithArgs(value: CharSequence): Int {
            return value.lastIndexOf('o', 3, true)
        }

        fun stringLastChar(value: String): Int {
            return value.lastIndexOf('A', 2, false)
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let callInfos = allMemberCallInfos(
            named: "lastIndexOf",
            in: ast,
            interner: interner,
            sourceManager: ctx.sourceManager
        )
        #expect(callInfos.count == 6, "Expected six lastIndexOf calls in user source")

        var boundToCharLink = 0
        for info in callInfos {
            #expect(
                sema.bindings.exprTypes[info.exprID] == sema.types.intType,
                "lastIndexOf must return Int"
            )

            if let chosenCallee = sema.bindings.callBinding(for: info.exprID)?.chosenCallee {
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_lastIndexOf_char",
                    "Expected lastIndexOf(Char,...) to resolve to kk_string_lastIndexOf_char"
                )
                boundToCharLink += 1
            }
        }
        #expect(boundToCharLink >= 2, "Expected at least two lastIndexOf calls to bind to kk_string_lastIndexOf_char")

        let memberFQName = ["kotlin", "text", "lastIndexOf"].map { interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(links.contains("kk_string_lastIndexOf_char"))
        #expect(links.contains("kk_string_lastIndexOf"))
        #expect(links.contains("kk_string_lastIndexOf_ignoreCase"))
    }
}
