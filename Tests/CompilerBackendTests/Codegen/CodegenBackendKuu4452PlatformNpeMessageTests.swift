#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

/// KUU-4452: a bundled java.util platform `T!` result used in a non-null
/// position raises the JVM `checkNotNullExpressionValue` NPE
/// `"<call>(...) must not be null"` — catchable, so `e.message` is
/// observable. Platform values reaching non-null positions through locals
/// or `!!` keep the plain message-less NPE, and discarded/nullable poll
/// results leave the deque throwing NoSuchElementException afterwards.
@Suite
struct CodegenBackendKuu4452PlatformNpeMessageTests {
    @Test
    func platformCallResultsCarryJvmCheckNotNullMessage() throws {
        let source = """
        import java.util.ArrayDeque

        fun main() {
            val dq = ArrayDeque<Int>()
            try {
                println(dq.poll())
            } catch (e: NullPointerException) {
                println("poll:${e.message}")
            }
            try {
                println(dq.peek())
            } catch (e: NullPointerException) {
                println("peek:${e.message}")
            }
            try {
                val v: Int = dq.pollFirst()
                println(v)
            } catch (e: NullPointerException) {
                println("pollFirst:${e.message}")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Kuu4452PlatformNpeCall",
            expected: """
            poll:poll(...) must not be null
            peek:peek(...) must not be null
            pollFirst:pollFirst(...) must not be null

            """
        )
    }

    @Test
    func platformLocalAndBangKeepPlainNpe() throws {
        let source = """
        import java.util.ArrayDeque

        fun main() {
            val dq = ArrayDeque<Int>()
            val parked = dq.pollFirst()
            try {
                val v: Int = parked
                println(v)
            } catch (e: NullPointerException) {
                println("parked:${e.message}")
            }
            val bare: Int? = null
            try {
                println(bare!!)
            } catch (e: NullPointerException) {
                println("bang:${e.message}")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Kuu4452PlatformNpeLocal",
            expected: "parked:null\nbang:null\n"
        )
    }

    @Test
    func pollAndPeekLeaveDequeThrowingNoSuchElement() throws {
        let source = """
        import java.util.ArrayDeque

        fun main() {
            val dq = ArrayDeque<Int>()
            dq.poll()
            try {
                println(dq.element())
            } catch (e: Throwable) {
                println("element:${e::class.simpleName}")
            }
            dq.peek()
            try {
                println(dq.removeFirst())
            } catch (e: Throwable) {
                println("removeFirst:${e::class.simpleName}")
            }
            try {
                println(dq.remove())
            } catch (e: Throwable) {
                println("remove:${e::class.simpleName}")
            }
            try {
                println(dq.pop())
            } catch (e: Throwable) {
                println("pop:${e::class.simpleName}")
            }
            val strings = ArrayDeque<String>()
            println("str-poll:${strings.poll()}")
            try {
                println(strings.element())
            } catch (e: Throwable) {
                println("str-element:${e::class.simpleName}")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Kuu4452DequeAfterEmptyPoll",
            expected: """
            element:NoSuchElementException
            removeFirst:NoSuchElementException
            remove:NoSuchElementException
            pop:NoSuchElementException
            str-poll:null
            str-element:NoSuchElementException

            """
        )
    }
}
#endif
