#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct AmbiguousSuperCallTests {
    private static let rejectSources = [
        """
        package superambiguity.original
        open class A2 { open fun f() = 1 }
        interface I2 { fun f() = 2 }
        class C3 : A2(), I2 { override fun f() = super.f() + 10 }
        fun main() { println(C3().f()) }
        """,
        """
        package superambiguity.interfaces
        interface A { fun f() = 1 }
        interface I { fun f() = 2 }
        class C : A, I { override fun f() = super.f() }
        """,
        """
        package superambiguity.reversed
        interface I { fun f() = 2 }
        open class A { open fun f() = 1 }
        class C : I, A() { override fun f() = super.f() }
        """,
        """
        package superambiguity.inherited
        open class Root { open fun f() = 1 }
        open class A : Root()
        interface I { fun f() = 2 }
        class C : A(), I { override fun f() = super.f() }
        """,
        """
        package superambiguity.overloads
        open class A { fun f(x: Int) = 1 }
        interface I { fun f(x: String) = 2 }
        class C : A(), I { fun g() = super.f(1) }
        """,
        """
        package superambiguity.arity
        open class A { fun f() = 1 }
        interface I { fun f(x: Int) = 2 }
        class C : A(), I { fun g() = super.f() }
        """,
        """
        package superambiguity.diamond
        interface Root { fun f() = 1 }
        interface A : Root
        interface I : Root
        class C : A, I { fun g() = super.f() }
        """,
        """
        package superambiguity.related
        interface A { fun f() = 1 }
        interface I : A { override fun f() = 2 }
        class C : A, I { override fun f() = super.f() }
        """,
        """
        package superambiguity.abstracts
        interface A { fun f(): Int }
        interface I { fun f(): Int }
        class C : A, I { override fun f() = super.f() }
        """,
        """
        package superambiguity.generic
        open class A<T> { open fun f(x: T) = 1 }
        interface I { fun f(x: Int) = 2 }
        class C : A<Int>(), I { override fun f(x: Int) = super.f(x) }
        """,
    ]
    private static let rejected = Result { try semaContext(for: rejectSources) }

    @Test func rejectsEachAmbiguousSuperCallWithoutCascadingErrors() throws {
        let ctx = try Self.rejected.get()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == Self.rejectSources.count, "Unexpected diagnostics: \(errors.map(\.message))")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0056" })
        #expect(errors.allSatisfy { $0.message.contains("super<Foo>") })
    }

    @Test func doesNotBindAmbiguousSuperCallsToAnImplementation() throws {
        let ctx = try Self.rejected.get()
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "f", in: ast, interner: ctx.interner).filter { id in
            guard case let .memberCall(receiver, _, _, _, _) = ast.arena.expr(id) else { return false }
            return if case .superRef = ast.arena.expr(receiver) { true } else { false }
        }
        #expect(calls.count == Self.rejectSources.count)
        for call in calls {
            #expect(sema.bindings.callBinding(for: call)?.chosenCallee == nil)
            #expect(sema.bindings.exprType(for: call) == sema.types.errorType)
        }
    }

    @Test func acceptsQualifiedAndUnambiguousSuperCalls() throws {
        let source = """
        open class Base { open fun f() = 1; fun classOnly() = 3 }
        interface Default { fun f() = 2; fun interfaceOnly() = 4 }
        class Qualified : Base(), Default {
            override fun f() = super<Base>.f() + super<Default>.f()
            fun distinct() = super.classOnly() + super.interfaceOnly()
        }
        open class Derived : Base()
        interface DerivedDefault : Default
        class Inherited : Derived(), DerivedDefault {
            override fun f() = super<Derived>.f() + super<DerivedDefault>.f()
        }
        interface Abstract { fun f(): Int }
        class ConcreteClass : Base(), Abstract { override fun f() = super.f() }
        abstract class AbstractClass { abstract fun f(): Int }
        class ConcreteInterface : AbstractClass(), Default { override fun f() = super.f() }
        open class Overloaded { fun f(x: Int) = x; fun f(x: String) = x }
        class Single : Overloaded() { fun g() = super.f(1) }
        open class Generic<T> { open fun value(x: T): T = x }
        class GenericChild : Generic<Int>() {
            override fun value(x: Int) = super.value(x)
            fun qualified(x: Int) = super<Generic>.value(x)
        }
        interface Left
        interface Right
        class AnyChild : Left, Right { override fun toString() = super.toString() }
        fun ordinaryCall() = Qualified().f()
        """
        let ctx = try semaContext(for: [source])
        #expect(!ctx.diagnostics.hasError, "Unexpected errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let owners = memberCallExprIDs(named: "f", in: ast, interner: ctx.interner).compactMap { call in
            guard let chosen = sema.bindings.callBinding(for: call)?.chosenCallee,
                  let owner = sema.symbols.parentSymbol(for: chosen),
                  let symbol = sema.symbols.symbol(owner)
            else { return String?.none }
            return ctx.interner.resolve(symbol.name)
        }
        #expect(owners.filter { $0 == "Base" }.count == 3)
        #expect(owners.filter { $0 == "Default" }.count == 3)
        #expect(owners.contains("Overloaded"))
        #expect(owners.contains("Qualified"))
    }

    @Test func concreteIteratorImplementationBeatsRuntimeBridge() throws {
        let source = """
        open class Base : Iterator<Int> {
            override fun hasNext(): Boolean = false
            override fun next(): Int = 7
        }
        class Child : Base(), MutableIterator<Int> {
            override fun next(): Int = super.next()
            override fun remove() {}
        }
        class Reversed : MutableIterator<Int>, Base() {
            override fun next(): Int = super.next()
            override fun remove() {}
        }
        class Qualified : Base(), MutableIterator<Int> {
            override fun next(): Int = super<Base>.next()
            override fun remove() {}
        }
        class BridgeOnly : Iterator<Int> {
            fun fallback(): Int = super.next()
        }
        """
        let ctx = try semaContext(for: [source])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let owners = memberCallExprIDs(named: "next", in: ast, interner: ctx.interner).compactMap { call in
            guard isUserSourceExpr(call, in: ctx),
                  case let .memberCall(receiver, _, _, _, _) = ast.arena.expr(call),
                  case .superRef = ast.arena.expr(receiver),
                  let chosen = sema.bindings.callBinding(for: call)?.chosenCallee,
                  let owner = sema.symbols.parentSymbol(for: chosen),
                  let symbol = sema.symbols.symbol(owner)
            else { return String?.none }
            return ctx.interner.resolve(symbol.name)
        }
        #expect(owners.filter { $0 == "Base" }.count == 3)
        #expect(owners.filter { $0 == "Iterator" }.count == 1)
        let bridge = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "Iterator", "next"].map(ctx.interner.intern)))
        #expect(sema.symbols.symbol(bridge)?.flags.contains(.abstractType) == false)
        #expect(sema.symbols.externalLinkName(for: bridge) == "kk_iterator_next")
    }

    @Test func concreteClassImplementationBeatsMutableSetBridges() throws {
        let source = """
        abstract class Base<E> : MutableSet<E> {
            override fun addAll(elements: Collection<E>): Boolean = true
            override fun retainAll(elements: Collection<E>): Boolean = true
            override fun removeAll(elements: Collection<E>): Boolean = true
            override fun containsAll(elements: Collection<E>): Boolean = false
        }
        class Builder<E> : Base<E>(), MutableSet<E> {
            fun addTo(elements: Collection<E>) = super.addAll(elements)
            fun retainFrom(elements: Collection<E>) = super.retainAll(elements)
            fun removeFrom(elements: Collection<E>) = super.removeAll(elements)
        }
        """
        let ctx = try semaContext(for: [source])
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["addAll", "retainAll", "removeAll"] {
            let owners = memberCallExprIDs(named: name, in: ast, interner: ctx.interner).compactMap { call in
                guard isUserSourceExpr(call, in: ctx),
                      case let .memberCall(receiver, _, _, _, _) = ast.arena.expr(call),
                      case .superRef = ast.arena.expr(receiver),
                      let chosen = sema.bindings.callBinding(for: call)?.chosenCallee,
                      let owner = sema.symbols.parentSymbol(for: chosen),
                      let symbol = sema.symbols.symbol(owner)
                else { return String?.none }
                return ctx.interner.resolve(symbol.name)
            }
            #expect(owners == ["Base"], "super.\(name) owners: \(owners)")
        }
    }
}
#endif
