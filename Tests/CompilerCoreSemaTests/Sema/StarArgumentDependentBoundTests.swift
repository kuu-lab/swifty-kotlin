@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct StarArgumentDependentBoundTests {
    @Test
    func boundOnStarProjectedSiblingAcceptsStarProjectedArgument() throws {
        let ctx = try semaContext(from: """
        interface Ext<C : Any>
        interface Factory<C : Any, E : Ext<C>>

        fun <T : Ext<*>> pick(factory: Factory<*, T>): Factory<*, T> = factory
        fun widen(factory: Factory<*, Ext<*>>): Factory<*, Ext<*>> = factory
        """)
        #expect(ctx.errorDiagnostics.isEmpty, "\(ctx.errorDiagnostics)")
    }

    @Test
    func boundOnConcreteSiblingStillRejectsMismatchedArgument() throws {
        _ = try semaContext(
            from: """
            interface Ext<C : Any>
            interface Factory<C : Any, E : Ext<C>>

            fun mismatch(factory: Factory<String, Ext<Int>>) {}
            """,
            expecting: [.error("KSWIFTK-SEMA-BOUND")]
        )
    }
}
