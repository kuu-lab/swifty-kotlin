#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct RangeGenericArgumentInferenceTests {
    @Test func literalsAndInferredLocalsSatisfyIntersectionBounds() throws {
        let ctx = makeContextFromSource("""
        fun <R> acceptInt(range: R): Boolean where R : ClosedRange<Int>, R : Iterable<Int> = true
        fun <R> acceptLong(range: R): Boolean where R : ClosedRange<Long>, R : Iterable<Long> = true
        fun <R> acceptChar(range: R): Boolean where R : ClosedRange<Char>, R : Iterable<Char> = true
        fun <R> acceptUInt(range: R): Boolean where R : ClosedRange<UInt>, R : Iterable<UInt> = true
        fun <R> acceptULong(range: R): Boolean where R : ClosedRange<ULong>, R : Iterable<ULong> = true
        class Acceptor {
            fun <R> acceptMember(range: R): Boolean where R : ClosedRange<Int>, R : Iterable<Int> = true
        }
        fun test() {
            acceptInt(1..10)
            val range = 1..10
            acceptInt(range)
            acceptInt(range = 1..10)
            acceptInt<IntRange>(1..10)
            acceptLong(1L..10L)
            acceptChar('a'..'z')
            acceptUInt(1u..10u)
            acceptULong(1uL..10uL)
            Acceptor().acceptMember(1..10)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let expectedTypes = [
            "acceptInt": "IntRange", "acceptLong": "LongRange", "acceptChar": "CharRange",
            "acceptUInt": "UIntRange", "acceptULong": "ULongRange", "acceptMember": "IntRange"
        ]
        var calls = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  let expectedName = expectedTypes[ctx.interner.resolve(symbol.name)]
            else { continue }
            let argumentType = try #require(binding.substitutedTypeArguments.first)
            guard case let .classType(classType) = sema.types.kind(of: argumentType) else {
                Issue.record("Expected nominal range argument, got \(sema.types.renderType(argumentType))")
                continue
            }
            #expect(sema.symbols.symbol(classType.classSymbol)?.name == ctx.interner.intern(expectedName))
            calls += 1
        }
        #expect(calls == 9)
    }

    @Test func unboundedInferenceAndOverloadsUseRangeInsteadOfScalar() throws {
        let ctx = makeContextFromSource("""
        fun <T> identity(value: T): T = value
        fun choose(value: Int): String = "scalar"
        fun <R> choose(value: R): String where R : ClosedRange<Int>, R : Iterable<Int> = "range"
        fun withLambda(range: Int, block: (String) -> Unit) {}
        fun <R> withLambda(range: R, block: (Int) -> Unit) where R : ClosedRange<Int>, R : Iterable<Int> {}
        fun test() {
            val range: IntRange = identity(1..3)
            choose(1..3)
            withLambda(1..3) { it + 1 }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  ["choose", "withLambda"].contains(ctx.interner.resolve(symbol.name))
            else { continue }
            #expect(sema.symbols.functionSignature(for: symbol.id)?.typeParameterSymbols.count == 1)
        }
    }

    @Test func conditionalRangesUseNestedSealedConstructorParameterType() throws {
        let ctx = makeContextFromSource("""
        class Solver {
            private sealed class Rule(val target: String) {
                companion object {
                    fun of(test: Char, amount: Int): Rule = RangeCheck('x',
                        if (test == '<') (1..<amount) else (amount + 1..4000),
                        if (test == '<') (amount..4000) else (1..amount), "A")

                    fun literal(): Rule = RangeCheck('x', 1..9, 10..4000, "A")
                }

                class RangeCheck(
                    val category: Char,
                    val range: IntRange,
                    val antiRange: IntRange,
                    target: String
                ) : Rule(target)
            }

            fun less(): String = Rule.of('<', 10).target
            fun greater(): String = Rule.of('>', 10).target
            fun literal(): String = Rule.literal().target
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        func isUserExpr(_ id: ExprID) -> Bool {
            guard let range = ast.arena.exprRange(id) else { return false }
            return ctx.sourceManager.origin(of: range.start.file) == .user
        }
        let conditionalExpressions = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard isUserExpr(id), case .ifExpr = ast.arena.expr(id) else { return nil }
            return id
        }
        #expect(conditionalExpressions.count == 2)
        #expect(conditionalExpressions.allSatisfy { sema.bindings.isRangeExpr($0) })

        let constructorCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard isUserExpr(id), case let .call(calleeID, _, _, _) = ast.arena.expr(id),
                  case let .nameRef(name, _) = ast.arena.expr(calleeID),
                  name == ctx.interner.intern("RangeCheck")
            else {
                return nil
            }
            return id
        }
        #expect(constructorCalls.count == 2)
        for call in constructorCalls {
            guard let binding = sema.bindings.callBinding(for: call) else {
                Issue.record("RangeCheck constructor call should resolve")
                continue
            }
            #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
        }
    }

    @Test(arguments: [
        "fun <R> accept(range: R) where R : ClosedRange<Long>, R : Iterable<Long> {}\nfun test() { accept(1..3) }",
        "fun accept(value: Int) {}\nfun test() { accept(1..3) }",
        "fun <R> accept(range: R) where R : ClosedRange<Int>, R : Iterable<Int> {}\nfun test() { accept(3) }",
        "fun <R> accept(range: R) where R : ClosedRange<Int>, R : Iterable<Int> {}\nfun test() { accept(3 downTo 1) }",
        "fun <R> accept(range: R) where R : ClosedRange<Int>, R : Iterable<Int> {}\nfun test() { val p = 1..3 step 2; accept(p) }",
        "fun <R> accept(range: R) where R : ClosedRange<Int>, R : Iterable<Int> {}\nfun test(range: IntRange?) { accept(range) }"
    ])
    func incompatibleBoundsAndScalarArgumentsRemainRejected(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
#endif
