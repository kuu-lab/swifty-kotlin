@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendFunctionTypedPropertyInvocationTests {
    @Test
    func functionTypedStoredPropertyInvokesThroughMemberCallSyntax() throws {
        let source = """
        class Holder(val f: (Int) -> Int)
        fun main() {
            val h = Holder({ x -> if (x > 0) x else -x })
            println(h.f(3))
            println(h.f(-5))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedPropertyInvocation",
            expected:
                """
                3
                5
                """
                + "\n"
        )
    }

    @Test
    func functionTypedPropertyWithUnitReturnInvokesThroughMemberCallSyntax() throws {
        let source = """
        class Box(val value: (String) -> Unit)
        fun main() {
            val box = Box({ s -> println(s) })
            box.value("x")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedPropertyUnitReturn",
            expected: "x\n"
        )
    }

    @Test
    func functionTypedPropertyWithTwoParametersInvokesThroughMemberCallSyntax() throws {
        let source = """
        class Holder(val f: (Int, Int) -> Int)
        fun main() {
            val h = Holder({ a, b -> a * 10 + b })
            println(h.f(3, 4))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedPropertyTwoParams",
            expected: "34\n"
        )
    }

    @Test
    func functionTypedPropertyReadThenInvokeStillWorks() throws {
        let source = """
        class Holder(val f: (Int) -> Int)
        fun main() {
            val h = Holder({ x -> if (x > 0) x else -x })
            val g = h.f
            println(g(3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedPropertyReadThenInvoke",
            expected: "3\n"
        )
    }

    @Test
    func functionTypedPropertyWithCustomGetterInvokesThroughMemberCallSyntax() throws {
        let source = """
        class Holder {
            private val impl: (Int) -> Int = { x -> x + 1 }
            val f: (Int) -> Int
                get() = impl
        }
        fun main() {
            println(Holder().f(3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedPropertyGetter",
            expected: "4\n"
        )
    }

    @Test
    func functionTypedInterfacePropertyDispatchesThroughItable() throws {
        let source = """
        interface HasF { val f: (Int) -> Int }
        class Impl : HasF {
            override val f: (Int) -> Int = { x -> x * 2 }
        }
        fun main() {
            val h: HasF = Impl()
            println(h.f(3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedInterfaceProperty",
            expected: "6\n"
        )
    }

    @Test
    func receiverFunctionTypedPropertyInvokesThroughMemberCallSyntax() throws {
        let source = """
        class Greeter(val greet: Greeter.(Int) -> String) {
            val name = "world"
        }
        fun main() {
            val g = Greeter({ n -> "hi " + name + " " + n })
            println(g.greet(7))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ReceiverFunctionTypedProperty",
            expected: "hi world 7\n"
        )
    }

    @Test
    func functionTypedPropertyInvokesThroughSafeCallSyntax() throws {
        let source = """
        class Holder(val f: (Int) -> Int)
        fun main() {
            val h: Holder? = Holder({ x -> x + 1 })
            val n: Holder? = null
            println(h?.f(3))
            println(n?.f(3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedPropertySafeCall",
            expected:
                """
                4
                null
                """
                + "\n"
        )
    }

    @Test
    func functionTypedObjectMemberInvokesThroughNameSyntax() throws {
        let source = """
        object Holder {
            val f: (Int) -> Int = { x -> x + 1 }
        }
        fun main() {
            println(Holder.f(3))
            println(Holder.f.invoke(3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedObjectMember",
            expected:
                """
                4
                4
                """
                + "\n"
        )
    }

    @Test
    func functionTypedObjectLiteralPropertyInvokesThroughMemberCallSyntax() throws {
        let source = """
        fun main() {
            val o = object {
                val f: (Int) -> Int = { x -> x + 1 }
                val g: () -> Int = { 7 }
            }
            println(o.f(3))
            println(o.g())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedObjectLiteralProperty",
            expected:
                """
                4
                7
                """
                + "\n"
        )
    }

    @Test
    func functionTypedPropertyWithZeroParametersInvokesThroughCallSyntax() throws {
        let source = """
        class Holder(val f: () -> Int)
        fun main() {
            val h = Holder({ 42 })
            val n: Holder? = Holder({ 7 })
            println(h.f())
            println(n?.f())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedPropertyZeroParams",
            expected:
                """
                42
                7
                """
                + "\n"
        )
    }

    @Test
    func functionTypedPropertyInvokesThroughExplicitInvokeSyntax() throws {
        let source = """
        class Holder(val f: (Int) -> Int)
        fun main() {
            val h = Holder({ x -> x + 1 })
            println(h.f.invoke(3))
            val g: (Int) -> Int = { x -> x + 1 }
            println(g.invoke(3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FunctionTypedPropertyExplicitInvoke",
            expected:
                """
                4
                4
                """
                + "\n"
        )
    }

    @Test
    func nullableFunctionTypedPropertyInvokesThroughSafeInvokeSyntax() throws {
        let source = """
        class Holder(val f: ((Int) -> Int)?)
        fun main() {
            val h = Holder({ x -> x + 1 })
            println(h.f?.invoke(3))
            val n: Holder? = Holder({ x -> x + 1 })
            println(n?.f?.invoke(3))
            val e = Holder(null)
            println(e.f?.invoke(3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NullableFunctionTypedPropertyInvoke",
            expected:
                """
                4
                4
                null
                """
                + "\n"
        )
    }

    @Test
    func nullableFunctionTypedLocalInvokesThroughSafeInvokeSyntax() throws {
        let source = """
        fun main() {
            val g: ((Int) -> Int)? = { x -> x + 1 }
            println(g?.invoke(3))
            val z: ((Int) -> Int)? = null
            println(z?.invoke(3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NullableFunctionTypedLocalInvoke",
            expected:
                """
                4
                null
                """
                + "\n"
        )
    }
}

#endif
