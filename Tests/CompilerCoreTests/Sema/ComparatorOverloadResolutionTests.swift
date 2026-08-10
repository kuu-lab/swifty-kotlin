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

    // MARK: - Path-aware expression search helpers

    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func allExprIDs(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var result: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { result.append(exprID) }
        }
        return result
    }

    // MARK: - Consolidated overload resolution tests

    @Test
    func testComparatorOverloadResolutions() throws {

        let sources: [String] = [
            """
            fun noop() {}
            """,
            """
            fun sample0() {
                val cmp = compareBy<Int> { it * 2 }
                listOf(3, 1, 2).sortedWith(cmp)
            }
            """,
            """
            fun sample1() {
                val cmp = compareBy<String> { it.length }
                listOf("banana", "apple").sortedWith(cmp)
            }
            """,
            """
            fun sample2() {
                val cmp = compareBy<String>({ it.length }, { it })
                listOf("banana", "apple", "fig").sortedWith(cmp)
            }
            """,
            """
            fun sample3() {
                val cmp = compareBy<String>({ it.length }, { it.first() }, { it.last() })
                listOf("banana", "apple", "fig").sortedWith(cmp)
            }
            """,
            """
            fun sample4() {
                val cmp = compareBy<Int>({ it / 100 }, { it % 100 / 10 }, { it % 10 }, { -it })
                listOf(231, 132, 121, 221).sortedWith(cmp)
            }
            """,
            """
            fun sample6() {
                val cmp = compareBy<String> { it.length }.thenBy { it }
                listOf("banana", "apple").sortedWith(cmp)
            }
            """,
            """
            fun sample8() {
                val cmp = compareBy<String> { it.length }.thenByDescending { it }
                listOf("banana", "apple").sortedWith(cmp)
            }
            """,
            """
            fun sample9() {
                val cmp = compareBy<Int> { it % 10 }.thenByDescending { it / 10 }
                listOf(231, 114, 123).sortedWith(cmp)
            }
            """,
            """
            fun sample11() {
                val cmp = compareBy<Int> { it }.reversed()
                listOf(3, 1, 2).sortedWith(cmp)
            }
            """,
            """
            fun sample12() {
                val cmp = compareBy<Int> { it }.reversed()
                listOf(3, 1, 2).sortedWith(cmp)
            }
            """,
            """
            fun sample15() {
                val cmp = naturalOrder<Int>()
                listOf(3, 1, 2).sortedWith(cmp)
            }
            """,
            """
            fun sample16() {
                val cmp = reverseOrder<Int>()
                listOf(3, 1, 2).sortedWith(cmp)
            }
            """,
            """
            fun sample21() {
                val cmp = compareBy<Int> { it }.nullsFirst()
                listOf(3, 1, 2).sortedWith(cmp)
            }
            """,
            """
            fun sample22() {
                val cmp = compareBy<Int> { it }.nullsLast()
                listOf(3, 1, 2).sortedWith(cmp)
            }
            """,
            """
            fun sample25() {
                val cmp = compareBy<Int> { it % 10 }
                    .thenBy { it / 10 }
                    .reversed()
                listOf(231, 114, 123).sortedWith(cmp)
            }
            """,
            """
            fun sample26() {
                val a = compareBy<Int> { it }.nullsFirst()
                val b = compareBy<Int> { it }.nullsLast()
                listOf(3, 1, 2).sortedWith(a)
                listOf(3, 1, 2).sortedWith(b)
            }
            """,
            """
            fun sample27(values: List<Int?>) {
                val a = compareBy<Int?> { it }.nullsFirst()
                val b = compareBy<Int?> { it }.nullsLast()
                values.sortedWith(a)
                values.sortedWith(b)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected comparator tests to type-check without diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            // paths[0] is the noop source; paths[1...] map to the original sample sources.

            // === testCompareByLambdaOverloadSelectsSourceBackedVariant ===

            do {

                           let callExpr = try #require(firstExprID(in: ast, path: paths[1], ctx: ctx) { _, expr in
                               guard case let .call(calleeExpr, _, _, _) = expr,
                                     case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                               else { return false }
                               return interner.resolve(calleeName) == "compareBy"
                           }, "Expected a call to compareBy")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected overload resolution to produce a chosen callee for compareBy { }")
                           let symbol = try #require(sema.symbols.symbol(chosenCallee))
                           #expect(symbol.fqName.map { interner.resolve($0) } == ["kotlin", "comparisons", "compareBy"], "Expected compareBy<Int> { } to resolve to the bundled stdlib compareBy")
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected compareBy<Int> { } to be source-backed without a runtime comparator link")

            }

            // === testCompareByLambdaProducesComparatorReturnType ===

            do {

                           let callExpr = try #require(firstExprID(in: ast, path: paths[2], ctx: ctx) { _, expr in
                               guard case let .call(calleeExpr, _, _, _) = expr,
                                     case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                               else { return false }
                               return interner.resolve(calleeName) == "compareBy"
                           })

                           let exprType = try #require(sema.bindings.exprTypes[callExpr])
                           guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                               Issue.record("Expected compareBy result to be a class type (Comparator<T>)")
                               return
                           }
                           let symbol = try #require(sema.symbols.symbol(ct.classSymbol))
                           #expect(symbol.fqName.map { interner.resolve($0) } == ["kotlin", "Comparator"], "Expected compareBy { } to return kotlin.Comparator<T>")

            }

            // === testCompareByTwoSelectorsResolvesToMultiSelectorOverload ===

            do {

                           let callExpr = try #require(allExprIDs(in: ast, path: paths[3], ctx: ctx) { _, expr in
                                   guard case let .call(calleeExpr, _, args, _) = expr,
                                         case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                                   else { return false }
                                   return interner.resolve(calleeName) == "compareBy" && args.count == 2
                               }.first, "Expected 2-selector compareBy call")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected overload resolution to produce a chosen callee for compareBy(s1, s2)")
                           let sig = try #require(sema.symbols.functionSignature(for: chosenCallee))
                           #expect(sig.parameterTypes.count == 2, "Expected 2-param signature for 2-selector compareBy")
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected 2-selector compareBy to be bundled Kotlin source")

            }

            // === testCompareByThreeSelectorsResolvesToMultiSelectorOverload ===

            do {

                           let callExpr = try #require(allExprIDs(in: ast, path: paths[4], ctx: ctx) { _, expr in
                                   guard case let .call(calleeExpr, _, args, _) = expr,
                                         case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                                   else { return false }
                                   return interner.resolve(calleeName) == "compareBy" && args.count == 3
                               }.first, "Expected 3-selector compareBy call")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected overload resolution to produce a chosen callee for compareBy(s1, s2, s3)")
                           let sig = try #require(sema.symbols.functionSignature(for: chosenCallee))
                           #expect(sig.parameterTypes.count == 3, "Expected 3-param signature for 3-selector compareBy")
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected 3-selector compareBy to be bundled Kotlin source")

            }

            // === testCompareByFourSelectorsResolvesToVarargMultiSelectorOverload ===

            do {

                           let callExpr = try #require(allExprIDs(in: ast, path: paths[5], ctx: ctx) { _, expr in
                                   guard case let .call(calleeExpr, _, args, _) = expr,
                                         case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                                   else { return false }
                                   return interner.resolve(calleeName) == "compareBy" && args.count == 4
                               }.first, "Expected 4-selector compareBy call")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected overload resolution to produce a chosen callee for compareBy(vararg selectors)")
                           let sig = try #require(sema.symbols.functionSignature(for: chosenCallee))
                           #expect(sig.parameterTypes.count == 1, "Expected single vararg parameter for 4-selector compareBy")
                           #expect(sig.valueParameterIsVararg == [true])
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected vararg compareBy to be bundled Kotlin source")
                           let varargMapping = try #require(sema.bindings.callBinding(for: callExpr)?.parameterMapping)
                           #expect(
                               (0..<4).allSatisfy { varargMapping[$0] == 0 },
                               "Every vararg selector argument must map to the vararg parameter; got: \(varargMapping)"
                           )

            }

            // === testThenByIsRegisteredAsSyntheticComparatorMember ===

            do {

                           let symbolID = try #require(sourceBackedComparatorExtension(
                               named: "thenBy",
                               sema: sema,
                               interner: interner
                           ), "Expected source-backed Comparator.thenBy to be registered")
                           #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.thenBy to be source-backed")

            }

            // === testThenByChainedOnCompareByResolvesCorrectly ===

            do {

                           let callExpr = try #require(firstExprID(in: ast, path: paths[6], ctx: ctx) { _, expr in
                               guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                               return interner.resolve(callee) == "thenBy"
                           }, "Expected a thenBy member call")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected thenBy to resolve to a callee")
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected thenBy to be source-backed")

            }

            // === testThenByDescendingIsRegisteredAsSyntheticComparatorMember ===

            do {

                           let symbolID = try #require(sourceBackedComparatorExtension(
                               named: "thenByDescending",
                               sema: sema,
                               interner: interner
                           ), "Expected source-backed Comparator.thenByDescending to be registered")
                           #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.thenByDescending to be source-backed")

            }

            // === testThenByDescendingChainedOnCompareByResolvesCorrectly ===

            do {

                           let callExpr = try #require(firstExprID(in: ast, path: paths[7], ctx: ctx) { _, expr in
                               guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                               return interner.resolve(callee) == "thenByDescending"
                           }, "Expected a thenByDescending member call")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected thenByDescending to resolve to a callee")
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected thenByDescending to be source-backed")

            }

            // === testThenByDescendingReturnTypeIsComparator ===

            do {

                           let callExpr = try #require(firstExprID(in: ast, path: paths[8], ctx: ctx) { _, expr in
                               guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                               return interner.resolve(callee) == "thenByDescending"
                           })

                           let exprType = try #require(sema.bindings.exprTypes[callExpr])
                           guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                               Issue.record("Expected thenByDescending result to be Comparator<T>")
                               return
                           }
                           let symbol = try #require(sema.symbols.symbol(ct.classSymbol))
                           #expect(symbol.fqName.map { interner.resolve($0) } == ["kotlin", "Comparator"], "Expected thenByDescending to return kotlin.Comparator<T>")

            }

            // === testReversedIsRegisteredAsSyntheticComparatorMember ===

            do {

                           let symbolID = try #require(sourceBackedComparatorExtension(
                               named: "reversed",
                               parameterCount: 0,
                               sema: sema,
                               interner: interner
                           ), "Expected source-backed Comparator.reversed to be registered")
                           #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.reversed to be source-backed")

            }

            // === testReversedCallOnComparatorResolvesCorrectly ===

            do {

                           let callExpr = try #require(firstExprID(in: ast, path: paths[9], ctx: ctx) { _, expr in
                               guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                               return interner.resolve(callee) == "reversed"
                           }, "Expected a reversed member call")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected reversed() to resolve to a callee")
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected reversed() to be source-backed")

            }

            // === testReversedReturnTypeIsComparator ===

            do {

                           let callExpr = try #require(firstExprID(in: ast, path: paths[10], ctx: ctx) { _, expr in
                               guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                               return interner.resolve(callee) == "reversed"
                           })

                           let exprType = try #require(sema.bindings.exprTypes[callExpr])
                           guard case let .classType(ct) = sema.types.kind(of: exprType) else {
                               Issue.record("Expected reversed() result to be Comparator<T>")
                               return
                           }
                           let symbol = try #require(sema.symbols.symbol(ct.classSymbol))
                           #expect(symbol.fqName.map { interner.resolve($0) } == ["kotlin", "Comparator"], "Expected reversed() to return kotlin.Comparator<T>")

            }

            // === testNaturalOrderIsRegisteredAsSyntheticTopLevelFunction ===

            do {

                           let symbolID = try #require(sema.symbols.lookup(fqName: [
                                   interner.intern("kotlin"),
                                   interner.intern("comparisons"),
                                   interner.intern("naturalOrder"),
                               ]), "Expected source-backed naturalOrder to be registered")
                           #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected naturalOrder() to be source-backed")

            }

            // === testReverseOrderIsRegisteredAsSyntheticTopLevelFunction ===

            do {

                           let symbolID = try #require(sema.symbols.lookup(fqName: [
                                   interner.intern("kotlin"),
                                   interner.intern("comparisons"),
                                   interner.intern("reverseOrder"),
                               ]), "Expected source-backed reverseOrder to be registered")
                           #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected reverseOrder() to be source-backed")

            }

            // === testNaturalOrderCallResolvesCorrectly ===

            do {

                           let callExpr = try #require(allExprIDs(in: ast, path: paths[11], ctx: ctx) { _, expr in
                                   guard case let .call(calleeExpr, _, _, _) = expr,
                                         case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                                   else { return false }
                                   return interner.resolve(calleeName) == "naturalOrder"
                               }.first, "Expected a naturalOrder() call")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected naturalOrder() to resolve to a callee")
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected naturalOrder() to be source-backed")

            }

            // === testReverseOrderCallResolvesCorrectly ===

            do {

                           let callExpr = try #require(allExprIDs(in: ast, path: paths[12], ctx: ctx) { _, expr in
                                   guard case let .call(calleeExpr, _, _, _) = expr,
                                         case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                                   else { return false }
                                   return interner.resolve(calleeName) == "reverseOrder"
                               }.first, "Expected a reverseOrder() call")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected reverseOrder() to resolve to a callee")
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected reverseOrder() to be source-backed")

            }

            // === testNaturalOrderSignatureHasNoParameters ===

            do {

                           let symbolID = try #require(sema.symbols.lookup(fqName: [
                               interner.intern("kotlin"),
                               interner.intern("comparisons"),
                               interner.intern("naturalOrder"),
                           ]))
                           let sig = try #require(sema.symbols.functionSignature(for: symbolID))
                           #expect(sig.parameterTypes.isEmpty, "Expected naturalOrder() to take no parameters")

            }

            // === testReverseOrderSignatureHasNoParameters ===

            do {

                           let symbolID = try #require(sema.symbols.lookup(fqName: [
                               interner.intern("kotlin"),
                               interner.intern("comparisons"),
                               interner.intern("reverseOrder"),
                           ]))
                           let sig = try #require(sema.symbols.functionSignature(for: symbolID))
                           #expect(sig.parameterTypes.isEmpty, "Expected reverseOrder() to take no parameters")

            }

            // === testNullsFirstIsRegisteredAsSourceBackedComparatorExtension ===

            do {

                           let symbolID = try #require(sourceBackedComparatorExtension(
                               named: "nullsFirst",
                               parameterCount: 0,
                               sema: sema,
                               interner: interner
                           ), "Expected source-backed Comparator.nullsFirst to be registered")
                           #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.nullsFirst to be bundled Kotlin source")

            }

            // === testNullsLastIsRegisteredAsSourceBackedComparatorExtension ===

            do {

                           let symbolID = try #require(sourceBackedComparatorExtension(
                               named: "nullsLast",
                               parameterCount: 0,
                               sema: sema,
                               interner: interner
                           ), "Expected source-backed Comparator.nullsLast to be registered")
                           #expect(sema.symbols.externalLinkName(for: symbolID) == nil, "Expected Comparator.nullsLast to be bundled Kotlin source")

            }

            // === testNullsFirstCallOnComparatorResolvesCorrectly ===

            do {

                           let callExpr = try #require(firstExprID(in: ast, path: paths[13], ctx: ctx) { _, expr in
                               guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                               return interner.resolve(callee) == "nullsFirst"
                           }, "Expected a nullsFirst member call")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected nullsFirst() to resolve to a callee")
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected nullsFirst() to resolve to bundled Kotlin source")

            }

            // === testNullsLastCallOnComparatorResolvesCorrectly ===

            do {

                           let callExpr = try #require(firstExprID(in: ast, path: paths[14], ctx: ctx) { _, expr in
                               guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                               return interner.resolve(callee) == "nullsLast"
                           }, "Expected a nullsLast member call")

                           let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee, "Expected nullsLast() to resolve to a callee")
                           #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected nullsLast() to resolve to bundled Kotlin source")

            }

            // === testNullsFirstSignatureHasNoParameters ===

            do {

                           let symbolID = try #require(sourceBackedComparatorExtension(
                               named: "nullsFirst",
                               parameterCount: 0,
                               sema: sema,
                               interner: interner
                           ))
                           let sig = try #require(sema.symbols.functionSignature(for: symbolID))
                           #expect(sig.parameterTypes.isEmpty, "Expected nullsFirst() to take no parameters")

            }

            // === testNullsLastSignatureHasNoParameters ===

            do {

                           let symbolID = try #require(sourceBackedComparatorExtension(
                               named: "nullsLast",
                               parameterCount: 0,
                               sema: sema,
                               interner: interner
                           ))
                           let sig = try #require(sema.symbols.functionSignature(for: symbolID))
                           #expect(sig.parameterTypes.isEmpty, "Expected nullsLast() to take no parameters")

            }

            // === testChainedCompareByThenByReversedResolvesCleanly ===

            do {

                           #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected no diagnostics for chained compareBy.thenBy.reversed(), got: \(ctx.diagnostics.diagnostics)")

            }

            // === testNullsFirstAndNullsLastReturnComparatorType ===

            do {

                           #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected no diagnostics for nullsFirst/nullsLast usage, got: \(ctx.diagnostics.diagnostics)")

            }

            // === testNullableCompareBySelectorCanFeedNullsFirstAndLast ===

            do {

                           #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected nullable compareBy selectors to resolve, got: \(ctx.diagnostics.diagnostics)")

            }

        }
    }

    /// KSP-461: with several lambda arguments the parameter type has to come from
    /// the call's explicit type argument, otherwise the implicit `it` of each
    /// lambda stays unresolved (`KSWIFTK-SEMA-0022`).
    @Test func testImplicitItResolvesInMultiSelectorCompareByWithExplicitTypeArgument() throws {
        let source = """
        data class Row(val group: Int, val name: String)

        fun sample(rows: List<Row>) {
            rows.sortedWith(compareBy<Row>({ it.group }, { it.name }))
            rows.sortedWith(compareBy<Row>({ it.group }, { it.name }, { it.name.length }))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected implicit `it` to resolve from the explicit type argument, got: \(errors)")
        }
    }

    /// Same inference path on a plain user function: the explicit type argument
    /// must reach every lambda argument, not just the first one.
    @Test func testImplicitItResolvesForUserGenericOverloadWithExplicitTypeArgument() throws {
        let source = """
        fun <T> pick(selector: (T) -> Int): Int = 0
        fun <T> pick(selector1: (T) -> Int, selector2: (T) -> Int): Int = 1

        fun sample() {
            pick<Int>({ it }, { it + 1 })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected implicit `it` to resolve in both lambdas, got: \(errors)")
        }
    }
}
#endif
