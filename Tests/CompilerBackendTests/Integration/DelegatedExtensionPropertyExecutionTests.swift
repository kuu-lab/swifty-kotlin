@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct DelegatedExtensionPropertyExecutionTests {
    @Test func testTopLevelExtensionDelegateLinksAndReceivesExtensionReceiver() throws {
        let source = """
        import kotlin.reflect.KProperty

        class A
        class Delegate {
            operator fun getValue(thisRef: A, property: KProperty<*>): Int = 1
        }

        val A.prop: Int by Delegate()

        fun main() {
            println(A().prop)
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "1\n",
            moduleName: "KUU2132TopLevelExtensionDelegate"
        )
    }

    @Test func testMemberExtensionDelegateLinksAndReceivesExtensionReceiver() throws {
        let source = """
        import kotlin.reflect.KProperty

        class Delegate {
            operator fun getValue(thisRef: F.A, property: KProperty<*>): Int = 1
        }

        class F {
            val A.prop: Int by Delegate()

            class A

            fun value(): Int = A().prop
        }

        fun main() {
            println(F().value())
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "1\n",
            moduleName: "KUU2132MemberExtensionDelegate"
        )
    }

    @Test func testSameNamedExtensionDelegatesHaveSeparateStorage() throws {
        let source = """
        open class C
        object O : C()
        object K : C()

        class Delegate(private val value: String) {
            operator fun getValue(thisRef: C, property: Any): String = value
        }

        val O.prop by Delegate("O")
        val K.prop by Delegate("K")

        fun main() {
            print(O.prop + K.prop)
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "OK",
            moduleName: "KUU2132SameNamedExtensionDelegates"
        )
    }
}
