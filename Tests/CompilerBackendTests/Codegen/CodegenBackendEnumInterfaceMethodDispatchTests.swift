#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

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
    func testAbstractOverrideImplementedByEnumEntries() throws {
        let source = """
        interface T { fun f(): String }
        enum class E : T {
            ENTRY { override fun f() = "entry" },
            OTHER { override fun f() = "other" };
            abstract override fun f(): String
        }
        fun main() {
            println(E.ENTRY.f())
            println(E.OTHER.f())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumAbstractOverrideEntries",
            expected:
                """
                entry
                other
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
