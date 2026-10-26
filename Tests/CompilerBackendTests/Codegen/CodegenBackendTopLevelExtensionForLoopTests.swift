#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite
struct CodegenBackendTopLevelExtensionForLoopTests {
    @Test
    func closedRangeDoubleIteratorExtensionDrivesFloatingPointForIn() throws {
        try assertKotlinOutput(
            """
            operator fun ClosedRange<Double>.iterator() = object : Iterator<Double> {
                private var cur = start
                override fun hasNext() = cur <= endInclusive
                override fun next(): Double { val n = cur; cur += 0.1; return n }
            }

            fun main() {
                var sum = 0.0
                for (value in 0.0..1.0) sum += value
                println(sum)
            }
            """,
            moduleName: "ClosedRangeDoubleIteratorForIn",
            expected: "5.5\n"
        )
    }

    @Test
    func topLevelExtensionIteratorRunsBothSimpleAndGenericForLoops() throws {
        let source = """
        class Values(val value: String)
        operator fun Values.iterator(): Iterator<String> = object : Iterator<String> {
            var count = 0
            override fun hasNext(): Boolean = count < 2
            override fun next(): String { count++; return value }
        }

        abstract class FList<T> {
            abstract val head: T
            abstract val tail: FList<T>
            abstract val empty: Boolean

            companion object {
                val emptyFList = object : FList<Any>() {
                    override val head: Any get() = throw UnsupportedOperationException()
                    override val tail: FList<Any> get() = this
                    override val empty: Boolean get() = true
                }
            }

            operator fun plus(head: T): FList<T> = object : FList<T>() {
                override val head: T get() = head
                override val empty: Boolean get() = false
                override val tail: FList<T> get() = this@FList
            }
        }

        @Suppress("UNCHECKED_CAST")
        fun <T> emptyFList(): FList<T> = FList.emptyFList as FList<T>

        fun <T> FList<T>.reverse(where: FList<T> = emptyFList<T>()): FList<T> =
            if (empty) where else tail.reverse(where + head)

        operator fun <T> FList<T>.iterator(): Iterator<T> = object : Iterator<T> {
            private var current: FList<T> = this@iterator
            override fun next(): T {
                val result = current.head
                current = current.tail
                return result
            }
            override fun hasNext(): Boolean = !current.empty
        }

        fun main() {
            var simple = ""
            for (value in Values("Z")) simple += value
            println(simple)

            var result = ""
            for (value in (emptyFList<String>() + "O" + "K").reverse()) result += value
            println(result)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TopLevelExtensionForLoop",
            expected: "ZZ\nOK\n"
        )
    }
}
#endif
