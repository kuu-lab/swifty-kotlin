#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite struct DelegationBoundIdentityTests {
    @Test func originalReproducerAcceptsConcreteAndInterfaceCalls() throws {
        let ctx = makeBoundIdentityContext("""
        interface Bounded {
            fun <T : CharSequence> echo(value: T): T
            fun <T : Number> echo(value: T): T
        }
        class BoundedImpl : Bounded {
            override fun <T : CharSequence> echo(value: T): T = value
            override fun <T : Number> echo(value: T): T = value
        }
        class BoundedDelegate(base: Bounded) : Bounded by base
        fun main() {
            val concrete = BoundedDelegate(BoundedImpl())
            val control: Bounded = concrete
            val text: String = concrete.echo("text")
            val number: Int = concrete.echo(7)
            val controlText: String = control.echo("control")
            val controlNumber: Int = control.echo(9)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func distinctMethodBoundsKeepBothForwarders() throws {
        let ctx = makeBoundIdentityContext("""
        interface Bounded {
            fun <T : CharSequence> echo(value: T): T
            fun <T : Number> echo(value: T): T
        }
        class Wrapped(base: Bounded) : Bounded by base
        class Explicit(base: Bounded) : Bounded by base {
            override fun <E : Number> echo(value: E): E = value
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        for (name, count) in [("Wrapped", 2), ("Explicit", 1)] {
            let owner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern(name)]))
            #expect(sema.symbols.classDelegationForwardingMethodSymbols(forClass: owner).count == count)
        }
    }

    @Test func boundsAreSpecializedAndComparedAsUnorderedSets() throws {
        let ctx = makeBoundIdentityContext("""
        class Payload<out T>
        interface Variant { fun <T : Number> read(value: Payload<out T>): Int }
        class Covariant(base: Variant) : Variant by base {
            override fun <E : Number> read(value: Payload<E>): Int = 1
        }
        interface BoundPayload<out A>
        interface BoundVariant { fun <T : BoundPayload<out Number>> read(value: T): T }
        class CovariantBound(base: BoundVariant) : BoundVariant by base {
            override fun <E : BoundPayload<Number>> read(value: E): E = value
        }
        interface First
        interface Second
        interface Generic<A> {
            fun <T : A> read(value: T): T
        }
        class Specialized(base: Generic<First>) : Generic<First> by base {
            override fun <E : First> read(value: E): E = value
        }
        interface Multiple {
            fun <T> read(value: T): T where T : First, T : Second
        }
        class Reordered(base: Multiple) : Multiple by base {
            override fun <E> read(value: E): E where E : Second, E : First = value
        }
        interface Unbounded { fun <T> read(value: T): T }
        class ExplicitAny(base: Unbounded) : Unbounded by base {
            override fun <E : Any?> read(value: E): E = value
        }
        interface ExplicitBound { fun <T : Any?> read(value: T): T }
        class ImplicitAny(base: ExplicitBound) : ExplicitBound by base {
            override fun <E> read(value: E): E = value
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        for name in ["Specialized", "Reordered", "ExplicitAny", "ImplicitAny", "Covariant", "CovariantBound"] {
            let owner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern(name)]))
            #expect(sema.symbols.classDelegationForwardingMethodSymbols(forClass: owner).isEmpty, "\(name)")
        }
    }

    @Test func unrelatedArgumentsCannotSatisfyEitherBound() throws {
        let ctx = makeBoundIdentityContext("""
        interface Bounded {
            fun <T : CharSequence> echo(value: T): T
            fun <T : Number> echo(value: T): T
        }
        class Wrapped(base: Bounded) : Bounded by base
        fun rejected(base: Bounded) {
            Wrapped(base).echo(true)
            base.echo(true)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-BOUND" || $0.code == "KSWIFTK-SEMA-0002"
        }.count == 2)
    }
}
#endif
