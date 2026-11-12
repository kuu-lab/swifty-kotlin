import Foundation
@testable import CompilerCore
import Testing

@Suite(.serialized)
struct InterfaceStringABIAndGenericVirtualDispatchTests {
    @Test
    func interfaceStringSetterDispatchThroughAbstractIntersectionAndEnumEntry() throws {
        let source = """
        abstract class A {
            abstract val x: String
        }
        interface B {
            var x: String
        }
        abstract class C : A(), B
        class D(override var x: String) : C()

        enum class MutableEnum : B {
            A { override var x: String = "before" }
        }

        fun assignViaAbstractIntersection(c: C) {
            c.x = "intersection-ok"
        }

        fun main() {
            val d = D("fail")
            assignViaAbstractIntersection(d)
            println(d.x)

            val viaInterface: B = MutableEnum.A
            viaInterface.x = "enum-ok"
            println(viaInterface.x)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "InterfaceStringSetterDispatch",
            expected: """
            intersection-ok
            enum-ok

            """
        )
    }

    @Test
    func abstractGenericReturnMethodWithStringParameterInNestedObject() throws {
        let source = """
        abstract class Base<T : Any> {
            abstract fun convert(input: String): T
        }
        class Holder {
            object Impl : Base<String>() {
                override fun convert(input: String): String = input
            }
        }
        fun main() {
            val b: Base<String> = Holder.Impl
            println(b.convert("nested-ok"))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "AbstractGenericReturnWithStringParam",
            expected: """
            nested-ok

            """
        )
    }
}
