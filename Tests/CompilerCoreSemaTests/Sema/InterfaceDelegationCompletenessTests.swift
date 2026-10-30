#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite struct InterfaceDelegationCompletenessTests {
    private static let positiveContext = Result {
        let ctx = makeContextFromSource("""
        object SharedArrayList : MutableList<Any> by mutableListOf()
        class ListWrapper<T>(delegate: MutableList<T>) : MutableList<T> by delegate
        object SharedSet : MutableSet<Int> by mutableSetOf()
        object SharedMap : MutableMap<String, Int> by mutableMapOf()
        interface Parent<T> { fun read(): T; var value: T }
        interface Left<T> : Parent<T>
        interface Right<T> : Parent<T>
        interface Child<T> : Left<T>, Right<T>
        class Impl : Child<Int> {
            override fun read(): Int = value
            override var value: Int = 7
        }
        object Delegated : Child<Int> by Impl()
        class Outer {
            class Nested<T>(delegate: Child<T>) : Child<T> by delegate
            object NestedObject : Child<Int> by Impl()
            companion object : Child<Int> by Impl()
        }
        """)
        try runSema(ctx)
        return ctx
    }

    @Test func collectionAndInheritedDelegationSatisfiesAbstractMembers() throws {
        let ctx = try Self.positiveContext.get()
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func superclassDelegationSatisfiesDerivedInterfaceMembers() throws {
        let ctx = makeContextFromSource("""
        interface ImmutableCollection<out E> : Collection<E>
        interface ImmutableSet<out E> : Set<E>, ImmutableCollection<E>
        open class ImmutableCollectionAdapter<E>(private val impl: Collection<E>) :
            ImmutableCollection<E>, Collection<E> by impl
        open class IntermediateAdapter<E>(impl: Collection<E>) : ImmutableCollectionAdapter<E>(impl)
        class ImmutableSetAdapter<E>(impl: Set<E>) :
            ImmutableSet<E>, ImmutableCollectionAdapter<E>(impl)
        class DeepImmutableSetAdapter<E>(impl: Set<E>) :
            ImmutableSet<E>, IntermediateAdapter<E>(impl)
        class DirectImmutableSetAdapter<E>(impl: Set<E>) :
            ImmutableSet<E>, Set<E> by impl
        class ExplicitImmutableSetAdapter<E>(private val impl: Set<E>) :
            ImmutableSet<E>, ImmutableCollectionAdapter<E>(impl) {
            override fun containsAll(elements: Collection<E>): Boolean = impl.containsAll(elements)
        }
        """)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func inheritedDelegationDoesNotHideReabstractedOrUnrelatedMembers() throws {
        let ctx = makeContextFromSource("""
        interface ImmutableCollection<out E> : Collection<E>
        interface ImmutableSet<out E> : Set<E>, ImmutableCollection<E>
        interface ReabstractedSet<out E> : ImmutableSet<E> {
            abstract override fun containsAll(elements: Collection<E>): Boolean
        }
        interface NeedsValue { fun required(): Int }
        open class ImmutableCollectionAdapter<E>(private val impl: Collection<E>) :
            ImmutableCollection<E>, Collection<E> by impl
        class ReabstractedAdapter<E>(impl: Set<E>) :
            ReabstractedSet<E>, ImmutableCollectionAdapter<E>(impl)
        class MissingUnrelatedMember(impl: Set<Int>) :
            ImmutableSet<Int>, ImmutableCollectionAdapter<Int>(impl), NeedsValue
        """)
        try runSema(ctx)

        let abstractErrors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ABSTRACT" }
        #expect(abstractErrors.count == 2, "Got: \(abstractErrors)")
        #expect(abstractErrors.contains { $0.message.contains("containsAll") })
        #expect(abstractErrors.contains { $0.message.contains("required") })
    }

    @Test func objectDelegateExpressionIsPreservedAndReceivesExpectedType() throws {
        let ctx = try Self.positiveContext.get()
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let objectID = try #require(ast.sortedFiles.flatMap(\.topLevelDecls).first {
            guard case let .objectDecl(decl) = ast.arena.decl($0) else { return false }
            return decl.name == ctx.interner.intern("SharedArrayList")
        })
        guard case let .objectDecl(decl) = ast.arena.decl(objectID) else {
            Issue.record("Expected SharedArrayList object")
            return
        }
        let expression = try #require(decl.superTypeEntries.first?.delegateExpression)
        let delegateType = try #require(sema.bindings.exprType(for: expression))
        guard case let .classType(type) = sema.types.kind(of: delegateType) else {
            Issue.record("Expected a nominal delegate type")
            return
        }
        #expect(type.args == [.invariant(sema.types.anyType)])
        let symbol = try #require(sema.bindings.declSymbols[objectID])
        let interfaces = sema.symbols.delegatedInterfaces(forClass: symbol)
        #expect(interfaces.count == 1)
        let interface = try #require(interfaces.first)
        #expect(sema.symbols.classDelegationExpr(forClass: symbol, interface: interface) == expression)
    }

    @Test func diamondAndNestedDeclarationsSynthesizeInheritedForwardersOnce() throws {
        let ctx = try Self.positiveContext.get()
        let sema = try #require(ctx.sema)
        for path in [["Delegated"], ["Outer", "Nested"], ["Outer", "NestedObject"], ["Outer", "Companion"]] {
            let symbol = try #require(sema.symbols.lookup(fqName: path.map { ctx.interner.intern($0) }))
            let methods = sema.symbols.classDelegationForwardingMethodSymbols(forClass: symbol)
            let properties = sema.symbols.classDelegationForwardingPropertySymbols(forClass: symbol)
            #expect(methods.count == 1)
            #expect(properties.count == 1)
            #expect(sema.symbols.symbol(methods[0])?.flags.contains(.abstractType) == false)
            #expect(sema.symbols.symbol(properties[0])?.flags.contains(.mutable) == true)
            let signature = try #require(sema.symbols.functionSignature(for: methods[0]))
            #expect(signature.returnType == sema.symbols.propertyType(for: properties[0]))
            if path != ["Outer", "Nested"] {
                #expect(signature.returnType == sema.types.intType)
            }
        }
    }

    @Test func delegationDoesNotHideUnrelatedMissingMembersOrInvalidDelegates() throws {
        let ctx = makeContextFromSource("""
        interface Parent { fun read(): Int }
        interface Child : Parent
        interface Other { fun missing(): Int; val missingValue: Int }
        class Impl : Child { override fun read(): Int = 1 }
        object Partial : Child by Impl(), Other
        class Outer { object NestedPartial : Child by Impl(), Other }
        object WrongType : Child by 1
        open class Base
        object WrongSupertype : Base by Base()
        """)
        try runSema(ctx)
        let abstractErrors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ABSTRACT" }
        #expect(abstractErrors.count == 4, "Got: \(abstractErrors)")
        #expect(abstractErrors.allSatisfy { $0.message.contains("missing") })
        assertHasDiagnostic("KSWIFTK-SEMA-DELEGATE", in: ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func delegatedOperatorMembersKeepConventionFlags() throws {
        let ctx = makeContextFromSource("""
        interface Indexed {
            operator fun get(i: Int): Int
            operator fun contains(x: Int): Boolean
        }
        class C(val d: Indexed) : Indexed by d
        fun use(c: C): Int = c[3]
        fun has(c: C, x: Int): Boolean = x in c
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func delegatedMembersAreVisibleInsideDelegatingClassMethods() throws {
        let ctx = makeContextFromSource("""
        interface Trait { fun foo() = "O"; fun bar(): String }
        class SimpleClass : Trait { override fun bar() = "K" }
        class ComplexClass : Trait by SimpleClass() {
            fun qux() = foo() + bar()
        }
        fun directCall(complex: ComplexClass): String = complex.foo()
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let delegatingClass = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("ComplexClass")]))
        let forwardingMethods = Set(sema.symbols.classDelegationForwardingMethodSymbols(forClass: delegatingClass))
        let resolvedDelegatedCalls = sema.bindings.callBindings.values.filter {
            forwardingMethods.contains($0.chosenCallee)
        }
        #expect(
            resolvedDelegatedCalls.count == 3,
            "Expected foo() and bar() in qux(), plus complex.foo(), to bind to forwarding methods"
        )
    }

    @Test func directDelegationSatisfiesSiblingInterfaceAbstractMember() throws {
        // KUU-3248: a `by`-delegated implementation supplies `foo()` for every
        // supertype with a compatible signature, including sibling interfaces
        // that are not part of the delegated interface's closure.
        let ctx = makeContextFromSource("""
        interface A { fun foo(): Int }
        interface B { fun foo(): Int }
        class Z(private val a: A) : A by a, B
        interface CovA { fun cov(): Int }
        interface CovB { fun cov(): Number }
        class CovZ(private val a: CovA) : CovA by a, CovB
        interface NullA { fun nullable(): Int }
        interface NullB { fun nullable(): Int? }
        class NullZ(private val a: NullA) : NullA by a, NullB
        interface PropA { val prop: Int }
        interface PropB { val prop: Int }
        class PropZ(private val a: PropA) : PropA by a, PropB
        interface VarA { var v: Int }
        interface VarB { var v: Int }
        class VarZ(private val a: VarA) : VarA by a, VarB
        interface GenA<T> { fun pick(t: T): Int }
        interface GenB { fun pick(t: String): Int }
        interface GenC<T> { fun pick(t: T): Int }
        class GenZ(private val a: GenA<String>) : GenA<String> by a, GenB
        class GenericZ<T>(private val a: GenA<T>) : GenA<T> by a, GenC<T>
        open class Mid(private val a: A) : A by a
        class InheritedZ(a: A) : Mid(a), B
        class Impl : A { override fun foo(): Int = 1 }
        class ExplicitZ(private val a: A) : A by a, B {
            override fun foo(): Int = 2
        }
        fun runAll(z: Z, c: CovZ, n: NullZ, p: PropZ, v: VarZ, g: GenZ, h: GenericZ<String>, i: InheritedZ, e: ExplicitZ): Int =
            z.foo() + c.cov() + (n.nullable() ?: 0) + p.prop + v.v + g.pick("x") + h.pick("y") + i.foo() + e.foo()
        fun runLiteral(): Int {
            val literal = object : A by Impl(), B {}
            return literal.foo()
        }
        """)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func delegationDoesNotSatisfySiblingWithIncompatibleSignature() throws {
        // The delegated implementation only covers a sibling's abstract member
        // when the substituted signatures agree: arity, parameter types,
        // return-type covariance, and `var` invariance must all hold.
        let ctx = makeContextFromSource("""
        interface A { fun foo(): Int }
        interface ArityB { fun foo(n: Int): Int }
        class ArityZ(private val a: A) : A by a, ArityB
        interface RetB { fun foo(): String }
        class RetZ(private val a: A) : A by a, RetB
        interface WideA { fun wide(): Number }
        interface NarrowB { fun wide(): Int }
        class NarrowZ(private val a: WideA) : WideA by a, NarrowB
        interface ParamA { fun takes(n: Int): Int }
        interface ParamB { fun takes(s: String): Int }
        class ParamZ(private val a: ParamA) : ParamA by a, ParamB
        interface ValA { val prop: Int }
        interface VarB { var prop: Int }
        class ValZ(private val a: ValA) : ValA by a, VarB
        interface VarPropA { var n: Int }
        interface VarWideB { var n: Number }
        class VarWideZ(private val a: VarPropA) : VarPropA by a, VarWideB
        class NoImpl(val x: Int) : B2
        interface B2 { fun bar(): Int }
        """)
        try runSema(ctx)

        let abstractErrors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ABSTRACT" }
        #expect(abstractErrors.count == 7, "Got: \(abstractErrors)")
    }

    @Test func nestedGenericDelegatingConstructorSubstitutesItsResult() throws {
        let ctx = makeContextFromSource("""
        interface Parent<T> { fun read(): T }
        class Impl : Parent<Int> { override fun read(): Int = 7 }
        class Outer {
            class Nested<T>(delegate: Parent<T>) : Parent<T> by delegate
            class Empty<T>
        }
        val inferred: Parent<Int> = Outer.Nested(Impl())
        val explicit: Parent<Int> = Outer.Nested<Int>(Impl())
        val empty: Outer.Empty<Int> = Outer.Empty<Int>()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
