#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNullsFirstComparatorFunctionTests {
    @Test func testNullsFirstComparatorFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsFirst
        import kotlin.comparisons.naturalOrder

        fun makeComparator(): Comparator<Int?> {
            return nullsFirst(naturalOrder<Int>())
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testNestedComparatorSelectorsReceiveConcreteExpectedTypes() throws {
        let cases: [(expression: String, nullable: Bool)] = [
            ("listOf<P?>(P(1), null).sortedWith(nullsFirst(compareBy { it!!.k }))", false),
            ("listOf<P?>(P(1), null).sortedWith(nullsLast(compareByDescending { it!!.k }))", false),
            ("nullsFirst(compareBy { it!!.k })", false),
            ("listOf<P?>(P(1), null).sortedWith(nullsFirst(compareBy<P?> { it!!.k }))", true),
            ("listOf<P?>(P(1), null).sortedWith(compareBy { it!!.k })", true),
            ("listOf(P(1)).sortedWith(compareBy { it.k })", false),
            ("listOf<P?>(P(1), null).sortedWith(nullsFirst(compareBy { p -> p!!.k }))", false),
            ("listOf<P?>(P(1), null).sortedWith(nullsFirst(compareBy({ it!!.k }, { it!!.k })))", false),
        ]
        let functions = cases.enumerated().map { index, testCase in
            let resultType = index == 2 ? "Comparator<P?>" : "List<P?>"
            return "fun sample\(index)(): \(resultType) = \(testCase.expression)"
        }.joined(separator: "\n")
        let ctx = makeContextFromSource("data class P(val k: Int)\n" + functions)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = ast.arena.exprs.indices.compactMap { index -> (ExprID, [CallArgument])? in
            let id = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(id, in: ctx),
                  case let .call(callee, _, args, _) = ast.arena.expr(id),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ["compareBy", "compareByDescending"].contains(ctx.interner.resolve(name))
            else { return nil }
            return (id, args)
        }
        #expect(calls.count == cases.count)
        for ((call, arguments), testCase) in zip(calls, cases) {
            let binding = try #require(sema.bindings.callBinding(for: call))
            let elementType = try #require(binding.substitutedTypeArguments.first)
            guard case let .classType(element) = sema.types.kind(of: elementType) else {
                Issue.record("Expected concrete P selector parameter, got \(elementType)")
                continue
            }
            #expect(sema.symbols.symbol(element.classSymbol)?.name == ctx.interner.intern("P"))
            #expect(element.nullability == (testCase.nullable ? .nullable : .nonNull))
            for argument in arguments {
                let lambdaType = try #require(sema.bindings.exprType(for: argument.expr))
                guard case let .functionType(lambda) = sema.types.kind(of: lambdaType) else {
                    Issue.record("Expected selector lambda type")
                    continue
                }
                #expect(lambda.params == [elementType])
            }
        }
    }

    @Test func testNestedGenericFactoriesPreserveParameterNullability() throws {
        let ctx = makeContextFromSource("""
        data class P(val k: Int)
        class Selector<T>(val pick: (T) -> Int)
        fun <T> select(pick: (T) -> Int): Selector<T> = Selector(pick)
        fun <T : Any> nullableSelector(selector: Selector<in T>): Selector<T?> = TODO()
        fun <T> identitySelector(selector: Selector<T>): Selector<T> = selector
        fun nullableResult(): Selector<P?> = nullableSelector(select { it!!.k })
        fun nullableParameter(): Selector<P?> = identitySelector(select { it!!.k })
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let parameterNullabilities = ast.arena.exprs.indices.compactMap { index -> Nullability? in
            let id = ExprID(rawValue: Int32(index))
            guard case .lambdaLiteral = ast.arena.expr(id),
                  let type = sema.bindings.exprType(for: id),
                  case let .functionType(lambda) = sema.types.kind(of: type),
                  let parameter = lambda.params.first,
                  case let .classType(element) = sema.types.kind(of: parameter),
                  sema.symbols.symbol(element.classSymbol)?.name == ctx.interner.intern("P")
            else { return nil }
            return element.nullability
        }
        #expect(parameterNullabilities == [.nonNull, .nullable])
    }
}
#endif
