#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct CompanionClassScopeTests {
    @Test func nestedSealedInterfaceCompanionPropertyHasConcreteTypeInIfJoin() throws {
        // The atomicfu API comes from the bundled stdlib.
        let ctx = makeContextFromSource("""
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
        """)
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
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0468" })
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

    /// KUU-3977: top-level `X.Companion` extensions stay callable without a
    /// receiver only from inside the companion's owner class — the same
    /// lexical scope that exposes companion members unqualified.
    @Test func companionExtensionsResolveInsideOwnerClassScope() throws {
        let ctx = makeContextFromSource("""
        class Foo {
            companion object
            fun pick(a: Int, b: Int) = min(a, b)
            fun pickMax(a: Int, b: Int) = max(a, b)
        }
        fun Foo.Companion.min(a: Int, b: Int) = if (a < b) a else b
        fun Foo.Companion.max(a: Int, b: Int) = if (a > b) a else b
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

    /// KUU-3971: classifiers nested in a companion object resolve by simple
    /// name inside the enclosing class body, like companion functions and
    /// properties already do.
    @Test func companionNestedClassifierResolvesUnqualifiedInClassBody() throws {
        let path = "/virtual/companion-nested-classifier.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data("""
        class D {
            companion object { internal enum class Part { X, Y } }
            internal fun f() = Part.X
        }
        """.utf8))
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func companionNestedClassConstructorResolvesUnqualifiedInClassBody() throws {
        let path = "/virtual/companion-nested-class-ctor.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data("""
        class D {
            companion object { class Nested(val v: Int) }
            fun f() = Nested(1)
        }
        """.utf8))
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    /// KUU-4388: named objects and non-inner nested classes are static — they
    /// must not resolve the enclosing class's instance members, which have no
    /// valid receiver there.
    @Test(arguments: [
        """
        class E {
            val x = 7
            companion object { val c = x }
        }
        """,
        """
        class E {
            val x = 7
            object Nested { val c = x }
        }
        """,
        """
        class E {
            val x = 7
            class Nested { val c = x }
        }
        """,
        """
        class E {
            fun l(): Int = 1
            companion object { fun g() = l() }
        }
        """,
        """
        class E {
            fun l(): Int = 1
            object Nested { fun g() = l() }
        }
        """,
    ])
    func staticNestedScopeCannotReadOuterInstanceMembers(source: String) throws {
        let path = "/virtual/static-nested-scope.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    /// KUU-4388: the same scopes must keep resolving members that do have a
    /// valid receiver — inner-class outer instances, enclosing singleton
    /// objects, the companion's own members, and enum entries.
    @Test func staticNestedScopeKeepsValidReceiverMembers() throws {
        let path = "/virtual/static-nested-scope-ok.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data("""
        open class B { val bx = 11 }
        interface I { val ix: Int }
        class E : B(), I {
            override val ix = 3
            val x = 7
            fun f() = x + bx + ix
            inner class Inner { fun g() = x + bx }
            class Nested { fun h() = 1 }
            companion object {
                val cv = 5
                fun cf() = cv
                fun make(): Nested? = null
            }
        }
        enum class En { A, B;
            companion object { fun pick() = A }
        }
        object O {
            val ox = 13
            class Inner2 { fun f() = ox }
            object Nested2 { val c = ox }
        }
        """.utf8))
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    /// KUU-4471: a superclass's companion members resolve unqualified inside
    /// subclass bodies — they behave like inherited statics, through any
    /// depth of inheritance and from lexically nested classes.
    @Test func superclassCompanionMembersResolveUnqualifiedInSubclass() throws {
        let path = "/virtual/superclass-companion.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data("""
        open class A {
            companion object {
                const val C = 2
                fun f(x: Int) = x + 1
            }
        }
        class B : A() {
            fun g(x: Int) = f(x) + C
        }
        open class Mid : A()
        class Leaf : Mid() {
            fun h(x: Int) = f(x)
        }
        class Outer {
            class Inner2 : A() {
                class Deep { fun k(x: Int) = f(x) }
            }
        }
        class Shadowed : A() {
            companion object { fun f(x: Int) = x + 100 }
            fun s(x: Int) = f(x)
        }
        """.utf8))
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
