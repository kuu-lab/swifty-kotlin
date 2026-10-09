#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// An enum value widened to an interface is a `kk_enum_box_ordinal` box
/// whose itable slots are registered at the boxing site (enum entries never
/// run a constructor). Only the interface->slot mapping and property getters
/// were registered there, so any interface *method* call through the box
/// panicked with `KSWIFTK-RUNTIME-0001` ("method not found in vtable/itable"),
/// whether the override lived in an entry body or the enum body. The box now
/// registers each method, through a bridge that unboxes the ordinal receiver
/// the enum member / `$enumEntryDispatch$` helper expects. Inline expansion
/// and statically called interface-receiver members (default methods,
/// callable-reference thunks) now box an enum argument for an interface slot
/// instead of passing the raw ordinal.
@Suite
struct CodegenBackendEnumInterfaceMethodDispatchTests {

    @Test
    func testEntryBodyAndEnumBodyOverridesDispatchThroughInterface() throws {
        let source = """
        interface I { fun f(): Int }
        enum class E : I { A { override fun f() = 1 }, B { override fun f() = 2 } }
        enum class F(val k: Int) : I { X(5); override fun f() = k + 1 }
        enum class G(val k: Int) : I { P(5) { override fun f() = k + 10 }; override fun f() = -1 }
        fun main() {
            val i: I = E.B
            println(i.f())
            val j: I = F.X
            println(j.f())
            println(listOf<I>(E.A, G.P).map { it.f() })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumInterfaceMethodDispatch",
            expected:
                """
                2
                6
                [1, 15]
                """
                + "\n"
        )
    }

    @Test
    func testEnumReachesInterfaceDefaultsLambdasAndCallableReferences() throws {
        let source = """
        interface J {
            fun g(x: Int): String
            fun h(): String = "h:" + g(0)
        }
        enum class G(val k: Int) : J {
            P(5), Q(9) { override fun h() = "Q-h" };
            override fun g(x: Int) = "$name:${k + x}"
        }
        fun call(fn: (J) -> String, x: J) = fn(x)
        fun main() {
            val p: J = G.P
            println(p.h())
            val q: J = G.Q
            println(q.h())
            println(G.P.h())
            val lambda: (J) -> String = { it.g(1) }
            println(lambda(G.Q))
            println(call(lambda, G.P))
            val ref: (J) -> String = J::h
            println(ref(G.P))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumInterfaceDefaultsLambdasRefs",
            expected:
                """
                h:P:5
                Q-h
                h:P:5
                Q:10
                P:6
                h:P:5
                """
                + "\n"
        )
    }
}
#endif
