#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CompanionClassScopeTests {
    @Test func nestedSealedInterfaceCompanionPropertyHasConcreteTypeInIfJoin() throws {
        // The external atomicfu API is supplied by a fixture, not the bundled stdlib.
        let ctx = makeContextFromSources(["""
        import kotlinx.atomicfu.*

        class Ch {
            private sealed interface Slot {
                companion object { val CLOSED = Closed(null) }
                data object Empty : Slot
                data class Closed(val cause: Throwable?) : Slot
            }
            private val slot: AtomicRef<Slot> = atomic(Slot.Empty)

            fun close(cause: Throwable?) {
                val c = if (cause != null) Slot.Closed(cause) else Slot.CLOSED
                slot.getAndSet(c)
            }
            private fun closed(cause: Throwable?) =
                if (cause != null) Slot.Closed(cause) else Slot.CLOSED
        }
        """, """
        package kotlinx.atomicfu
        class AtomicRef<T>(private var current: T) {
            fun getAndSet(value: T): T {
                val previous = current
                current = value
                return previous
            }
        }
        fun <T> atomic(value: T): AtomicRef<T> = AtomicRef(value)
        """])
        try runToKIR(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Got: \(errors)")

        let sema = try #require(ctx.sema)
        let closed = try #require(sema.symbols.lookup(fqName: [
            "Ch", "Slot", "Closed",
        ].map(ctx.interner.intern)))
        let property = try #require(sema.symbols.lookup(fqName: [
            "Ch", "Slot", "Companion", "CLOSED",
        ].map(ctx.interner.intern)))
        let closedType = sema.types.make(.classType(ClassType(
            classSymbol: closed, args: [], nullability: .nonNull
        )))
        #expect(sema.symbols.propertyType(for: property) == closedType)
        let function = try #require(sema.symbols.lookup(fqName: [
            "Ch", "closed",
        ].map(ctx.interner.intern)))
        #expect(sema.symbols.functionSignature(for: function)?.returnType == closedType)

        let companion = try #require(sema.symbols.lookup(fqName: [
            "Ch", "Slot", "Companion",
        ].map(ctx.interner.intern)))
        let lazyInitializerName = "__companion_lazy_init_\(companion.rawValue)"
        let module = try #require(ctx.kir)
        #expect(findAllKIRFunctions(in: module).filter {
            ctx.interner.resolve($0.name) == lazyInitializerName
        }.count == 1)
        let body = try findKIRFunctionBody(named: "close", in: module, interner: ctx.interner)
        #expect(body.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return ctx.interner.resolve(callee) == lazyInitializerName
        })
    }

    @Test(arguments: ["", "Factory"])
    func deeplyNestedCompanionPropertyResolvesInEarlierFunction(companionName: String) throws {
        let ctx = makeContextFromSource("""
        class Outer {
            class Inner {
                private fun closed(flag: Boolean) =
                    if (flag) Slot.Closed(null) else Slot.CLOSED
                private sealed interface Slot {
                    companion object \(companionName) { val CLOSED = Closed(null) }
                    data class Closed(val cause: Throwable?) : Slot
                }
            }
        }
        """)
        try runToKIR(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Got: \(errors)")

        let sema = try #require(ctx.sema)
        let closed = try #require(sema.symbols.lookup(fqName: [
            "Outer", "Inner", "Slot", "Closed",
        ].map(ctx.interner.intern)))
        let function = try #require(sema.symbols.lookup(fqName: [
            "Outer", "Inner", "closed",
        ].map(ctx.interner.intern)))
        let closedType = sema.types.make(.classType(ClassType(
            classSymbol: closed, args: [], nullability: .nonNull
        )))
        #expect(sema.symbols.functionSignature(for: function)?.returnType == closedType)
    }

    @Test func deeplyNestedCompanionInitializerIsRegisteredBeforeOuterFunction() throws {
        let ctx = makeContextFromSource("""
        import Outer.Inner.Slot as DeepSlot

        class Outer {
            fun value() = DeepSlot.VALUE
            class Inner {
                interface Slot {
                    companion object { val VALUE = 42 }
                }
            }
        }
        """)
        try runToKIR(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Got: \(errors)")
        let sema = try #require(ctx.sema)
        let companion = try #require(sema.symbols.lookup(fqName: [
            "Outer", "Inner", "Slot", "Companion",
        ].map(ctx.interner.intern)))
        let initializerName = "__companion_lazy_init_\(companion.rawValue)"
        let module = try #require(ctx.kir)
        #expect(findAllKIRFunctions(in: module).filter {
            ctx.interner.resolve($0.name) == initializerName
        }.count == 1)
        let body = try findKIRFunctionBody(named: "value", in: module, interner: ctx.interner)
        #expect(body.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return ctx.interner.resolve(callee) == initializerName
        })
    }

    @Test func invalidNestedCompanionPropertyStillReportsTypeError() throws {
        let ctx = makeContextFromSource("""
        class Outer {
            private sealed interface Slot {
                companion object { val CLOSED: String = 1 }
            }
            fun value() = Slot.CLOSED
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test(arguments: ["", "Factory"])
    func privateCompanionHelpersResolveFromOwner(companionName: String) throws {
        let ctx = makeContextFromSource("""
        class M {
            fun put(k: String): Int = helper(k)
            private companion object \(companionName) {
                private fun helper(s: String): Int = s.length
            }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let owner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("M")]))
        let companion = try #require(sema.symbols.companionObjectSymbol(for: owner))
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "put", in: module, interner: ctx.interner)
        let receivers = body.compactMap { instruction -> KIRExprID? in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                  let symbol,
                  sema.symbols.symbol(symbol)?.name == ctx.interner.intern("helper")
            else { return nil }
            #expect(sema.symbols.parentSymbol(for: symbol) == companion)
            return arguments.first
        }
        #expect(receivers.count == 1)
        let receiver = try #require(receivers.first)
        #expect(module.arena.expr(receiver) == .symbolRef(companion))
    }

    @Test(arguments: ["", "Factory"])
    func privateCompanionHelpersRemainInaccessibleOutsideOwner(companionName: String) throws {
        let ctx = makeContextFromSource("""
        class M {
            fun put(k: String): Int = helper(k)
            private companion object \(companionName) {
                private fun helper(s: String): Int = s.length
            }
        }
        fun outside(): Int = M.helper("blocked")
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" })
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" })
    }

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

    @Test func companionBodiesCanUseInferredInstanceMembers() throws {
        let ctx = makeContextFromSource("""
        class Dependent {
            val own = listOf(1, 2)
            fun ownItems() = own
            val initial = retrieve(this)
            init { println(retrieve(this)) }
            fun size() = result.size
            companion object {
                fun retrieve(d: Dependent) = d.ownItems().size
                val result = listOf(1)
            }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func invalidCompanionBodiesStillReportErrors() throws {
        let ctx = makeContextFromSource("""
        class Invalid {
            companion object {
                val value: String = 1
                fun missing() = unknown()
            }
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
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
