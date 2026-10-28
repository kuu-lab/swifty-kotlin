@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrivateMemberCandidateSelectionTests {
    @Test
    func accessibleInterfacePropertyWinsOverInheritedPrivateProperties() throws {
        try assertNoSemaErrors("""
        package test

        interface A {
            val c: String
                get() = "OK"
        }

        interface B {
            private val c: String
                get() = "FAIL"
        }

        open class C {
            private val c: String = "FAIL"
        }

        open class D : C(), A, B {
            val b = c
        }

        fun box(): String = D().c
        """)
    }

    @Test
    func lateinitPropertyWithPrivateSetterAllowsCompoundAssignment() throws {
        try assertNoSemaErrors("""
        class X {
            var value = ""

            operator fun plusAssign(data: String) {
                value += data
            }
        }

        abstract class A {
            lateinit var x: X
                private set

            fun init() {
                x = X()
            }
        }

        class B : A()

        fun box(): String {
            val a = B()
            a.init()
            a.x += "OK"
            return a.x.value
        }
        """)
    }

    @Test
    func propertyWithPrivateSetterAllowsCompoundAssignment() throws {
        try assertNoSemaErrors("""
        class X {
            var value = ""

            operator fun plusAssign(data: String) {
                value += data
            }
        }

        abstract class A {
            var x: X = X()
                private set
        }

        class B : A()

        fun box(): String {
            val a = B()
            a.x += "OK"
            return a.x.value
        }
        """)
    }

    private func assertNoSemaErrors(_ source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
    }
}
