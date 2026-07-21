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

    private func sourceBackedComparatorExtension(
        named name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = ["kotlin", "comparisons", name].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fqName).first { symbolID in
            guard sema.symbols.externalLinkName(for: symbolID) == nil,
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  let receiver = signature.receiverType,
                  case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiver)),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            return symbol.fqName.map { interner.resolve($0) } == ["kotlin", "Comparator"]
        }
    }

    @Test func testComparatorThenComparatorUsesBundledStdlibFunction() throws {
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
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected thenComparator to resolve to bundled stdlib source")
        }
    }

    @Test func testCompareByDescendingUsesBundledStdlibFunction() throws {
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
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected compareByDescending to resolve to bundled stdlib source")
        }
    }

    @Test func testComparatorThenDescendingUsesBundledStdlibFunction() throws {
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
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected thenDescending to resolve to bundled stdlib source")
        }
    }

    @Test func testComparatorThenByUsesBundledStdlibFunction() throws {
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
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected thenBy to resolve to bundled stdlib source")
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

    @Test func testComparatorThenComparatorIsRegisteredFromBundledStdlib() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sourceBackedComparatorExtension(
                named: "thenComparator",
                sema: sema,
                interner: ctx.interner
            ), "Expected Comparator.thenComparator to be registered from bundled stdlib source")
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.thenComparator to be source-backed")
        }
    }

    @Test func testComparatorThenDescendingIsRegisteredFromBundledStdlib() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sourceBackedComparatorExtension(
                named: "thenDescending",
                sema: sema,
                interner: ctx.interner
            ), "Expected Comparator.thenDescending to be registered from bundled stdlib source")
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.thenDescending to be source-backed")
        }
    }
}
#endif
