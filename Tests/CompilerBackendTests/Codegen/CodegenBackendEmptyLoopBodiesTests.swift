#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendEmptyLoopBodiesTests {
    @Test
    func semicolonBodiesKeepForWhileAndDoWhileControlFlow() throws {
        let source = """
        class CountingIterator(private val limit: Int) : Iterator<Int> {
            var index = 0
            override fun hasNext(): Boolean = index < limit
            override fun next(): Int = index++
        }

        fun main() {
            val iterator = CountingIterator(5)
            for (x in iterator);
            println(iterator.index)

            var doWhileCount = 0
            do while (doWhileCount++ < 5);
            println(doWhileCount)

            var whileCount = 0
            while (whileCount++ < 5);
            println(whileCount)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EmptyLoopBodies",
            expected: "5\n6\n6\n"
        )
    }
}
#endif
