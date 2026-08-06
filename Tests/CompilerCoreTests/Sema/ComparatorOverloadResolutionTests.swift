#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Sema-level overload resolution tests for Comparator composition APIs (STDLIB-COMP-002).
/// Covers: compareBy { } single-selector, compareBy(selector1, selector2, ...) multi-selector,
/// thenBy / thenByDescending chained on Comparator, Comparator.reversed(),
/// naturalOrder() / reverseOrder(), nullsFirst() / nullsLast() wrapping.
@Suite
struct ComparatorOverloadResolutionTests {

    // MARK: - Helpers

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
        parameterCount: Int? = nil,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = ["kotlin", "comparisons", name].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fqName).first { symbolID in
            guard sema.symbols.externalLinkName(for: symbolID) == nil,
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  let receiver = signature.receiverType,
                  case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiver)),
                  let symbol = sema.symbols.symbol(classType.classSymbol),
                  symbol.fqName.map({ interner.resolve($0) }) == ["kotlin", "Comparator"]
            else {
                return false
            }
            guard let parameterCount else {
                return true
            }
            return signature.parameterTypes.count == parameterCount
        }
    }

    // MARK: - compareBy { } single-selector overload

    @Test func testCompareByLambdaOverloadSelectsSourceBackedVariant() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it * 2 }
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { return false }
                return ctx.interner.resolve(calleeName) == "compareBy"
            }, "Expected a call to compareBy")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected overload resolution to produce a chosen callee for compareBy { }")
            let symbol = try #require(sema.symbols.symbol(chosenCallee))
            #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "comparisons", "compareBy"], "Expected compareBy<Int> { } to resolve to the bundled stdlib compareBy")
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected compareBy<Int> { } to be source-backed without a runtime comparator link")
        }
    }

    @Test func testCompareByLambdaProducesComparatorReturnType() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String> { it.length }
            listOf("banana", "apple").sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { return false }
                return ctx.interner.resolve(calleeName) == "compareBy"
            })

            let exprType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                Issue.record("Expected compareBy result to be a class type (Comparator<T>)")
                return
            }
            let symbol = try #require(sema.symbols.symbol(ct.classSymbol))
            #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "Comparator"], "Expected compareBy { } to return kotlin.Comparator<T>")
        }
    }

    // MARK: - compareBy(selector1, selector2, ...) multi-selector varargs

    @Test func testCompareByTwoSelectorsResolvesToMultiSelectorOverload() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String>({ it.length }, { it })
            listOf("banana", "apple", "fig").sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(allExprIDs(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "compareBy" && args.count == 2
                }.first, "Expected 2-selector compareBy call")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected overload resolution to produce a chosen callee for compareBy(s1, s2)")
            let sig = try #require(sema.symbols.functionSignature(for: chosenCallee))
            #expect(sig.parameterTypes.count == 1, "Expected the vararg selector overload for 2-selector compareBy")
            #expect(sig.valueParameterIsVararg == [true])
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected 2-selector compareBy to be source-backed")
        }
    }

    @Test func testCompareByThreeSelectorsResolvesToMultiSelectorOverload() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String>({ it.length }, { it.first() }, { it.last() })
            listOf("banana", "apple", "fig").sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(allExprIDs(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "compareBy" && args.count == 3
                }.first, "Expected 3-selector compareBy call")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected overload resolution to produce a chosen callee for compareBy(s1, s2, s3)")
            let sig = try #require(sema.symbols.functionSignature(for: chosenCallee))
            #expect(sig.parameterTypes.count == 1, "Expected the vararg selector overload for 3-selector compareBy")
            #expect(sig.valueParameterIsVararg == [true])
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected 3-selector compareBy to be source-backed")
        }
    }

    @Test func testCompareByFourSelectorsResolvesToVarargMultiSelectorOverload() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int>({ it / 100 }, { it % 100 / 10 }, { it % 10 }, { -it })
            listOf(231, 132, 121, 221).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(allExprIDs(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "compareBy" && args.count == 4
                }.first, "Expected 4-selector compareBy call")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected overload resolution to produce a chosen callee for compareBy(vararg selectors)")
            let sig = try #require(sema.symbols.functionSignature(for: chosenCallee))
            #expect(sig.parameterTypes.count == 1, "Expected single vararg parameter for 4-selector compareBy")
            #expect(sig.valueParameterIsVararg == [true])
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected 4-selector compareBy to be source-backed")
        }
    }

    // MARK: - thenBy { } chained

    @Test func testThenByIsRegisteredAsSyntheticComparatorMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sourceBackedComparatorExtension(
                named: "thenBy",
                sema: sema,
                interner: ctx.interner
            ), "Expected source-backed Comparator.thenBy to be registered")
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.thenBy to be source-backed")
        }
    }

    @Test func testThenByChainedOnCompareByResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String> { it.length }.thenBy { it }
            listOf("banana", "apple").sortedWith(cmp)
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
            }, "Expected a thenBy member call")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected thenBy to resolve to a callee")
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected thenBy to be source-backed")
        }
    }

    // MARK: - thenByDescending { } chained

    @Test func testThenByDescendingIsRegisteredAsSyntheticComparatorMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sourceBackedComparatorExtension(
                named: "thenByDescending",
                sema: sema,
                interner: ctx.interner
            ), "Expected source-backed Comparator.thenByDescending to be registered")
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.thenByDescending to be source-backed")
        }
    }

    @Test func testThenByDescendingChainedOnCompareByResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String> { it.length }.thenByDescending { it }
            listOf("banana", "apple").sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenByDescending"
            }, "Expected a thenByDescending member call")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected thenByDescending to resolve to a callee")
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected thenByDescending to be source-backed")
        }
    }

    @Test func testThenByDescendingReturnTypeIsComparator() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it % 10 }.thenByDescending { it / 10 }
            listOf(231, 114, 123).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "thenByDescending"
            })

            let exprType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                Issue.record("Expected thenByDescending result to be Comparator<T>")
                return
            }
            let symbol = try #require(sema.symbols.symbol(ct.classSymbol))
            #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "Comparator"], "Expected thenByDescending to return kotlin.Comparator<T>")
        }
    }

    // MARK: - Comparator.reversed()

    @Test func testReversedIsRegisteredAsSyntheticComparatorMember() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sourceBackedComparatorExtension(
                named: "reversed",
                parameterCount: 0,
                sema: sema,
                interner: ctx.interner
            ), "Expected source-backed Comparator.reversed to be registered")
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.reversed to be source-backed")
        }
    }

    @Test func testReversedCallOnComparatorResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it }.reversed()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "reversed"
            }, "Expected a reversed member call")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected reversed() to resolve to a callee")
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected reversed() to be source-backed")
        }
    }

    @Test func testReversedReturnTypeIsComparator() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it }.reversed()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "reversed"
            })

            let exprType = try #require(sema.bindings.exprTypes[callExpr])
            guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                Issue.record("Expected reversed() result to be Comparator<T>")
                return
            }
            let symbol = try #require(sema.symbols.symbol(ct.classSymbol))
            #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "Comparator"], "Expected reversed() to return kotlin.Comparator<T>")
        }
    }

    // MARK: - naturalOrder() / reverseOrder()

    @Test func testNaturalOrderIsRegisteredAsSyntheticTopLevelFunction() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("comparisons"),
                    ctx.interner.intern("naturalOrder"),
                ]), "Expected source-backed naturalOrder to be registered")
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected naturalOrder() to be source-backed")
        }
    }

    @Test func testReverseOrderIsRegisteredAsSyntheticTopLevelFunction() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("comparisons"),
                    ctx.interner.intern("reverseOrder"),
                ]), "Expected source-backed reverseOrder to be registered")
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected reverseOrder() to be source-backed")
        }
    }

    @Test func testNaturalOrderCallResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = naturalOrder<Int>()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(allExprIDs(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "naturalOrder"
                }.first, "Expected a naturalOrder() call")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected naturalOrder() to resolve to a callee")
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected naturalOrder() to be source-backed")
        }
    }

    @Test func testReverseOrderCallResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = reverseOrder<Int>()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(allExprIDs(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "reverseOrder"
                }.first, "Expected a reverseOrder() call")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected reverseOrder() to resolve to a callee")
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected reverseOrder() to be source-backed")
        }
    }

    @Test func testNaturalOrderSignatureHasNoParameters() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("comparisons"),
                ctx.interner.intern("naturalOrder"),
            ]))
            let sig = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(sig.parameterTypes.isEmpty, "Expected naturalOrder() to take no parameters")
        }
    }

    @Test func testReverseOrderSignatureHasNoParameters() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("comparisons"),
                ctx.interner.intern("reverseOrder"),
            ]))
            let sig = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(sig.parameterTypes.isEmpty, "Expected reverseOrder() to take no parameters")
        }
    }

    // MARK: - nullsFirst() / nullsLast()

    @Test func testNullsFirstIsRegisteredAsSourceBackedComparatorExtension() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            _ = try #require(sourceBackedComparatorExtension(
                named: "nullsFirst",
                parameterCount: 0,
                sema: sema,
                interner: ctx.interner
            ), "Expected source-backed Comparator<T>.nullsFirst() to be registered")
            #expect(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("Comparator"),
                ctx.interner.intern("nullsFirst"),
            ]) == nil, "nullsFirst must no longer be a synthetic Comparator member")
        }
    }

    @Test func testNullsLastIsRegisteredAsSourceBackedComparatorExtension() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            _ = try #require(sourceBackedComparatorExtension(
                named: "nullsLast",
                parameterCount: 0,
                sema: sema,
                interner: ctx.interner
            ), "Expected source-backed Comparator<T>.nullsLast() to be registered")
            #expect(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("Comparator"),
                ctx.interner.intern("nullsLast"),
            ]) == nil, "nullsLast must no longer be a synthetic Comparator member")
        }
    }

    @Test func testNullsFirstCallOnComparatorResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it }.nullsFirst()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "nullsFirst"
            }, "Expected a nullsFirst member call")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected nullsFirst() to resolve to a callee")
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected nullsFirst() to resolve to the source-backed extension")
            #expect(
                sema.symbols.symbol(chosenCallee)?.fqName.map { ctx.interner.resolve($0) }
                    == ["kotlin", "comparisons", "nullsFirst"]
            )
        }
    }

    @Test func testNullsLastCallOnComparatorResolvesCorrectly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it }.nullsLast()
            listOf(3, 1, 2).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "nullsLast"
            }, "Expected a nullsLast member call")

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected nullsLast() to resolve to a callee")
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected nullsLast() to resolve to the source-backed extension")
            #expect(
                sema.symbols.symbol(chosenCallee)?.fqName.map { ctx.interner.resolve($0) }
                    == ["kotlin", "comparisons", "nullsLast"]
            )
        }
    }

    @Test func testNullsFirstSignatureHasNoParameters() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sourceBackedComparatorExtension(
                named: "nullsFirst",
                sema: sema,
                interner: ctx.interner
            ))
            let sig = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(sig.parameterTypes.isEmpty, "Expected Comparator<T>.nullsFirst() to take no parameters")
        }
    }

    @Test func testNullsLastSignatureHasNoParameters() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sourceBackedComparatorExtension(
                named: "nullsLast",
                sema: sema,
                interner: ctx.interner
            ))
            let sig = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(sig.parameterTypes.isEmpty, "Expected Comparator<T>.nullsLast() to take no parameters")
        }
    }

    // MARK: - Chained composition: compareBy + thenBy + reversed

    @Test func testChainedCompareByThenByReversedResolvesCleanly() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<Int> { it % 10 }
                .thenBy { it / 10 }
                .reversed()
            listOf(231, 114, 123).sortedWith(cmp)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected no diagnostics for chained compareBy.thenBy.reversed(), got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func testNullsFirstAndNullsLastReturnComparatorType() throws {
        let source = """
        fun sample() {
            val a = compareBy<Int> { it }.nullsFirst()
            val b = compareBy<Int> { it }.nullsLast()
            listOf(3, 1, 2).sortedWith(a)
            listOf(3, 1, 2).sortedWith(b)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected no diagnostics for nullsFirst/nullsLast usage, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func testNullableCompareBySelectorCanFeedNullsFirstAndLast() throws {
        let source = """
        fun sample(values: List<Int?>) {
            val a = compareBy<Int?> { it }.nullsFirst()
            val b = compareBy<Int?> { it }.nullsLast()
            values.sortedWith(a)
            values.sortedWith(b)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected nullable compareBy selectors to resolve, got: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
