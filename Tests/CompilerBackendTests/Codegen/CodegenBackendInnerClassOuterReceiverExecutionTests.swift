#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendInnerClassOuterReceiverExecutionTests {
    @Test func unqualifiedOuterMemberCallUsesCapturedOuterInstance() throws {
        try assertKotlinOutput(
            """
            class Outer(val value: Int) {
                fun fetch(index: Int): Int = value + index
                inner class Inner {
                    fun compute(): Int = fetch(1)
                }
            }
            fun main() = println(Outer(7).Inner().compute())
            """,
            moduleName: "InnerClassOuterReceiverCall",
            expected: "8\n"
        )
    }

    @Test
    func qualifiedThisSelectsEnclosingInstanceWhenInnerClassExtendsOuterClass() throws {
        try assertKotlinOutput(
            """
            open class Outer private constructor(val s: String) {
                inner class Inner : Outer("O") {
                    fun foo() = this.s + this@Outer.s
                }
                class Nested : Outer("K")
                fun bar() = Inner()
            }
            fun main() { println(Outer.Nested().bar().foo()) }
            """,
            moduleName: "QualifiedThisWhenInnerExtendsOuter",
            expected: "OK\n"
        )
    }

    @Test func unqualifiedOuterMemberCallFromAnonymousObjectUsesCapturedOuterInstance() throws {
        try assertKotlinOutput(
            """
            interface Getter<E> {
                fun fetch(index: Int): E
            }
            class ConstGetter(val value: Int) : Getter<Int> {
                override fun fetch(index: Int): Int = value + index
                fun call(): Int {
                    val result = object : Any() {
                        fun compute(): Int = fetch(3)
                    }
                    return result.compute()
                }
            }
            fun main() = println(ConstGetter(7).call())
            """,
            moduleName: "AnonymousObjectOuterReceiverCall",
            expected: "10\n"
        )
    }

    @Test
    func localOwnerInnerConstructorCapturesEnclosingInstances() throws {
        try assertKotlinOutput(
            """
            class Host {
                val a = 1
                fun calculate(): Int {
                    class Owner {
                        val b = 2
                        inner class Child {
                            val c = 3
                            fun value() = this@Host.a + this@Owner.b + this.c
                        }
                    }
                    return Owner().Child().value()
                }
            }
            fun String.bar(): String {
                open class Local { fun result() = this@bar }
                class ExtensionOwner {
                    inner class Inner : Local() {
                        fun owner() = this@ExtensionOwner
                    }
                }
                return ExtensionOwner().Inner().result()
            }
            fun main() {
                println(Host().calculate())
                println("OK".bar())
            }
            """,
            moduleName: "LocalOwnerInnerConstructor",
            expected: "6\nOK\n"
        )
    }
}
#endif
