@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct ContextCallableReflectionTests {
    @Test
    func reflectionInvokerForwardsContextArgument() throws {
        let ctx = makeContextFromSource("""
        context(c: String) fun ctxLen(): Int = c.length
        fun <T> withCtx(v: String, f: context(String) () -> T): T = with(v) { f() }
        fun main() { println(withCtx("hi", ::ctxLen)) }
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let target = try findKIRFunction(named: "ctxLen", in: module, interner: ctx.interner)
        let invoker = try #require(findAllKIRFunctions(in: module).first { function in
            ctx.interner.resolve(function.name).hasPrefix("kk_reflect_invoke_")
                && function.body.contains { instruction in
                    guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                    return symbol == target.symbol
                }
        })
        let arguments = try #require(invoker.body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                  symbol == target.symbol else { return nil }
            return arguments
        }.first)
        #expect(target.params.count == 1)
        #expect(arguments.count == target.params.count)
        #expect(extractCallees(from: invoker.body, interner: ctx.interner).contains("__kk_list_get"))
    }

    @Test
    func unboundReceiverPrecedesContextAndValueArguments() throws {
        let ctx = makeContextFromSource("""
        context(c: String) fun Int.plusContext(delta: Int): Int = this + delta + c.length
        fun apply(f: context(String) (Int, Int) -> Int): Int = with("hi") { f(3, 4) }
        fun main() { println(apply(Int::plusContext)) }
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let target = try findKIRFunction(named: "plusContext", in: module, interner: ctx.interner)
        let invoker = try #require(findAllKIRFunctions(in: module).first { function in
            ctx.interner.resolve(function.name).hasPrefix("kk_reflect_invoke_")
                && function.body.contains { instruction in
                    guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                    return symbol == target.symbol
                }
        })
        let arguments = try #require(invoker.body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                  symbol == target.symbol else { return nil }
            return arguments
        }.first)
        #expect(target.params.count == 3)
        #expect(arguments.compactMap { module.arena.exprType($0) } == target.params.map(\.type))
    }

    @Test
    func reflectionInvokerForwardsMultipleContextsAndValueArgument() throws {
        let ctx = makeContextFromSource("""
        context(c: String, offset: Int) fun combine(value: Int): Int = c.length + offset + value
        fun apply(f: context(String, Int) (Int) -> Int): Int = f("hi", 3, 4)
        fun main() { println(apply(::combine)) }
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let target = try findKIRFunction(named: "combine", in: module, interner: ctx.interner)
        let invoker = try #require(findAllKIRFunctions(in: module).first { function in
            ctx.interner.resolve(function.name).hasPrefix("kk_reflect_invoke_")
                && function.body.contains { instruction in
                    guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                    return symbol == target.symbol
                }
        })
        let arguments = try #require(invoker.body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                  symbol == target.symbol else { return nil }
            return arguments
        }.first)
        #expect(target.params.count == 3)
        #expect(arguments.compactMap { module.arena.exprType($0) } == target.params.map(\.type))
    }
}
