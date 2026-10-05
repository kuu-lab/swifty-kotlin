#if canImport(Testing)
@testable import CompilerCore
import Testing

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

    @Test(arguments: [
        "fun <R> accept(range: R) where R : ClosedRange<Long>, R : Iterable<Long> {}\nfun test() { accept(1..3) }",
        "fun accept(value: Int) {}\nfun test() { accept(1..3) }",
        "fun <R> accept(range: R) where R : ClosedRange<Int>, R : Iterable<Int> {}\nfun test() { accept(3) }"
    ])
    func incompatibleBoundsAndScalarArgumentsRemainRejected(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
#endif
