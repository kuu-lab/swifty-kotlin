#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite
struct CodegenBackendMemberExtensionForLoopTests {
    @Test
    func lambdaParameterDestructuringCallsScopedExtensionComponents() throws {
        let source = """
        class A<T>(val x: Int, val y: Int, val z: Int)
        operator fun A<*>.component1() = x
        fun <T, R> foo(value: T, block: (T) -> R): R = block(value)
        object B {
            operator fun A<*>.component2() = y
            fun bar(): Int {
                operator fun <R> A<R>.component3() = z
                return foo(A<Int>(1, 2, 3)) { (x, y, z) -> x + y + z }
            }
            fun barWithCapturedLocal(): Int {
                val bonus = 4
                operator fun <R> A<R>.component3() = z + bonus
                return foo(A<Int>(1, 2, 3)) { (x, y, z) -> x + y + z }
            }
        }
        fun main() {
            val valid = B.bar() == 6 && B.barWithCapturedLocal() == 10
            val divisor = if (valid) 1 else 0
            val ignored = 12 / divisor
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "LambdaDestructuringExtensionComponents",
            expected: "",
            includeStdlib: false
        )
    }

    @Test
    func memberExtensionsImplementAllForLoopOperators() throws {
        let source = """
        class It {}
        class C {}
        class X {
            private var available = true
            operator fun It.hasNext() = if (available) { available = false; true } else false
            operator fun It.next() = 5
            operator fun C.iterator(): It = It()

            fun test() {
                for (i in C()) {
                    foo(i)
                }
            }
        }

        fun foo(x: Int) { println(x) }

        fun box(): String {
            X().test()
            return "OK"
        }

        fun main() { println(box()) }
        """
        try assertKotlinOutput(
            source,
            moduleName: "MemberExtensionForLoopAllOperators",
            expected: "5\nOK\n"
        )
    }

    @Test
    func memberExtensionNextWorksWithMemberIteratorAndHasNext() throws {
        let source = """
        class It {
            var hasNext = true
            operator fun hasNext() = if (hasNext) { hasNext = false; true } else false
        }

        class C {
            operator fun iterator(): It = It()
        }

        class X {
            operator fun It.next() = 5

            fun test() {
                for (i in C()) {
                    foo(i)
                }
            }
        }

        fun foo(x: Int) { println(x) }

        fun box(): String {
            X().test()
            return "OK"
        }

        fun main() { println(box()) }
        """
        try assertKotlinOutput(
            source,
            moduleName: "MemberExtensionForLoopNext",
            expected: "5\nOK\n"
        )
    }

    @Test
    func directMemberPriorityAndExplicitMemberExtensionCallsArePreserved() throws {
        let source = """
        class It {}
        class C {
            operator fun iterator(): It = It()
        }
        class Other
        class X {
            private var available = true

            operator fun Other.iterator(): It = It()
            operator fun C.iterator(): It = error("member extension must lose to C.iterator")
            operator fun It.hasNext() = if (available) { available = false; true } else false
            operator fun It.next() = 5

            fun testForIn() {
                for (value in C()) println(value)
            }

            fun testExplicitCalls() {
                available = true
                val iterator = Other().iterator()
                check(iterator.hasNext())
                check(iterator.next() == 5)
            }
        }

        fun main() {
            val x = X()
            x.testForIn()
            x.testExplicitCalls()
            println("OK")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "MemberExtensionForLoopPriority",
            expected: "5\nOK\n"
        )
    }
}
#endif
