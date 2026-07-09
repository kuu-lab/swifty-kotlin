@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testPrimitiveArgumentBoxedWhenPassedToSequenceOf() throws {
        let source = """
        fun main() {
            // Reported bug: sequenceOf(...) stores its elements into the same
            // erased-to-Any backing array as listOf/setOf, but skipped boxing.
            val chars = sequenceOf('a', 'b', 'c').toList()
            println(chars)

            // Boolean elements must render as true/false, not 0/1.
            val flags = sequenceOf(true, false).toList()
            println(flags)

            // Double elements must render as their value, not the raw bit pattern.
            val reals = sequenceOf(1.5, 2.5).toList()
            println(reals)

            // Regression: Int elements still render as their decimal value.
            val nums = sequenceOf(100, 200).toList()
            println(nums)

            // `is` checks against Any must see the concrete boxed type, not a
            // raw unboxed word.
            val firstInt: Any = sequenceOf(1, 2, 3).first()
            println(firstInt is Int)

            val firstChar: Any = sequenceOf('x', 'y').first()
            println(firstChar is Char)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "PrimitiveAutoboxingInSequenceOf",
            expected:
                """
                [a, b, c]
                [true, false]
                [1.5, 2.5]
                [100, 200]
                true
                true
                """
                + "\n"
        )
    }
}
