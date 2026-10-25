#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct SuperExpressionUseTests {
    @Test func rejectsBareSuperAsAnExpression() throws {
        let ctx = try semaContext(for: ["""
        class A { fun s() = super }
        fun main() {}
        """])

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Unexpected diagnostics: \(errors.map(\.message))")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0057")
        #expect(errors.first?.message == "'super' cannot be a callee.")
    }

    @Test func rejectsSuperAsACallCallee() throws {
        let ctx = try semaContext(for: ["""
        open class Base { open fun f() = 1 }
        class A : Base() { fun s() = super() }
        """])

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Unexpected diagnostics: \(errors.map(\.message))")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0057")
    }

    @Test func acceptsSuperAsAReceiver() throws {
        let ctx = try semaContext(for: ["""
        open class Base {
            open fun f() = 1
            operator fun plus(other: Int) = other
            operator fun unaryPlus() = 1
            operator fun get(index: Int) = index
            operator fun contains(value: Int) = true
        }
        class A : Base() {
            fun call() = super.f()
            fun plus() = super + 1
            fun unaryPlus() = +super
            fun indexed() = super[0]
            fun containsSuper() = 1 in super
        }
        """])

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map(\.message))")
    }
}
#endif
