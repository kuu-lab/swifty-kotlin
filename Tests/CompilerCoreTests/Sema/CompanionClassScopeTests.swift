#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CompanionClassScopeTests {
    @Test func inferredCompanionMembersResolveFromInstanceBodies() throws {
        let ctx = makeContextFromSource("""
        class A {
            val initialSize = xs.size
            init { println(getXs().size) }
            fun f() = xs.size
            fun g() = getXs().size
            fun h() = Companion.xs.size
            fun i() = A.xs.size
            fun textLength() = text.length
            fun firstElement() = xs.first()
            companion object {
                val xs = listOf(1)
                val text = "abc"
                fun getXs() = xs
            }
        }
        fun outside() = A.xs.size + A.text.length
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let companion = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("A"), ctx.interner.intern("Companion"),
        ]))
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "g", in: module, interner: ctx.interner)
        let receivers = body.compactMap { instruction -> KIRExprID? in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                  let symbol,
                  sema.symbols.symbol(symbol)?.name == ctx.interner.intern("getXs")
            else { return nil }
            return arguments.first
        }
        let receiver = try #require(receivers.first)
        #expect(module.arena.expr(receiver) == .symbolRef(companion))
    }

    @Test func instanceAndLocalMembersShadowCompanionMembers() throws {
        let ctx = makeContextFromSource("""
        class Shadow {
            val value = 11
            fun choose() = 12
            fun propertyValue(): Int = value
            fun functionValue(): Int = choose()
            fun localValue(): Int {
                val value = 13
                return value
            }
            companion object {
                val value = "companion"
                fun choose() = "companion"
            }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func interfaceBodiesResolveNamedCompanionMembers() throws {
        let ctx = makeContextFromSource("""
        interface Named {
            fun size() = xs.size + getXs().size + Factory.xs.size + Named.xs.size
            companion object Factory {
                val xs = listOf(1, 2)
                fun getXs() = xs
            }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
