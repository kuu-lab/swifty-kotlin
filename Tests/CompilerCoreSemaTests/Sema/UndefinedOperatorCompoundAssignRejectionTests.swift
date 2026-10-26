@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct UndefinedOperatorCompoundAssignRejectionTests {
    @Test
    func localVariableWithoutOperatorRejectsCompoundAssignment() throws {
        let ctx = makeContextFromSource("""
        class C(val s: String)
        fun test() {
            var c = C("a")
            c += C("b")
        }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test
    func localVariableWithoutMultiplyOperatorRejectsTimesAssign() throws {
        let ctx = makeContextFromSource("""
        class C(val s: String)
        fun test() {
            var c = C("a")
            c *= C("b")
        }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test
    func memberPropertyWithoutOperatorRejectsCompoundAssignment() throws {
        let ctx = makeContextFromSource("""
        class C(val s: String)
        class Container(var item: C)
        fun test(container: Container) {
            container.item += C("b")
        }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test
    func indexedElementWithoutOperatorRejectsCompoundAssignment() throws {
        let ctx = makeContextFromSource("""
        class C(val s: String)
        class CustomList {
            operator fun get(index: Int): C = C("a")
            operator fun set(index: Int, value: C) {}
        }
        fun test(list: CustomList) {
            list[0] += C("b")
        }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test
    func classWithPlusAssignAcceptsCompoundAssignment() throws {
        let ctx = makeContextFromSource("""
        class C(var s: String) {
            operator fun plusAssign(other: C) {
                s += other.s
            }
        }
        fun test() {
            var c = C("a")
            c += C("b")
        }
        """)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
