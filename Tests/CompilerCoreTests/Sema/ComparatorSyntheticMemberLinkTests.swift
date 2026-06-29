#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ComparatorSyntheticMemberLinkTests {
    private func allExprIDs(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }

    @Test func testComparatorThenComparatorUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: List<Int>) {
            val comparator = compareBy<Int> { it % 10 }.thenComparator { a, b -> b.compareTo(a) }
            values.sortedWith(comparator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenComparator"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_comparator_then_comparator", "Expected thenComparator to resolve to kk_comparator_then_comparator")
        }
    }

    @Test func testCompareByDescendingUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: List<Int>) {
            val comparator = compareByDescending<Int> { it % 10 }.thenBy { it / 10 }
            values.sortedWith(comparator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(allExprIDs(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(callee) else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "compareByDescending"
            }.first)

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_comparator_from_selector_primitive_descending", "Expected compareByDescending to resolve to kk_comparator_from_selector_primitive_descending")
        }
    }

    @Test func testComparatorThenDescendingUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: List<Int>) {
            val comparator = compareBy<Int> { it % 10 }.thenDescending { a, b -> b.compareTo(a) }
            values.sortedWith(comparator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenDescending"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_comparator_then_descending", "Expected thenDescending to resolve to kk_comparator_then_descending")
        }
    }

    @Test func testComparatorThenByUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: List<Int>) {
            val comparator = compareBy<Int> { it % 10 }.thenBy { it / 10 }
            values.sortedWith(comparator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenBy"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_comparator_then_by", "Expected thenBy to resolve to kk_comparator_then_by")
        }
    }

    @Test func testComparatorCompareMemberResolves() throws {
        let source = """
        fun render(values: List<Int>) {
            val comparator = compareBy<Int> { it % 10 }
            comparator.compare(13, 24)
            values.sortedWith(comparator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(allExprIDs(in: ast) { id, expr in
                // Skip bundled stdlib files (FileID 0 = collections, 1 = text, 2 = sequences, 3 = time, 4 = file IO);
                // maxWith/minWith bodies also call comparator.compare, which would
                // otherwise shadow the user's call with a lower ExprID.
                if let range = ast.arena.exprRange(id), range.start.file.rawValue < 5 {
                    return false
                }
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "compare"
            }.last)

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try #require(sema.symbols.symbol(chosenCallee))
            #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "Comparator", "compare"], "Expected Comparator.compare to resolve to the synthetic Comparator member")
        }
    }

    @Test func testComparatorThenComparatorIsRegisteredAsSyntheticMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Comparator"),
                        ctx.interner.intern("thenComparator"),
                    ]
                ), "Expected synthetic Comparator.thenComparator to be registered")
            #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_comparator_then_comparator", "Expected Comparator.thenComparator to map to kk_comparator_then_comparator")
        }
    }

    @Test func testComparatorThenDescendingIsRegisteredAsSyntheticMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Comparator"),
                        ctx.interner.intern("thenDescending"),
                    ]
                ), "Expected synthetic Comparator.thenDescending to be registered")
            #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_comparator_then_descending", "Expected Comparator.thenDescending to map to kk_comparator_then_descending")
        }
    }
}
#endif
