#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite struct KotlinCompilationRangeInterfaceTests {
    @Test func testCompile_openEndRangeInterfaceProperties() throws {
        try assertKotlinCompilesToKIR("""
        fun inspect(range: OpenEndRange<Int>): Int {
            val start = range.start
            val endExclusive = range.endExclusive
            return if (start < endExclusive) endExclusive else start
        }

        fun main() {
            val range: OpenEndRange<Int> = 1 ..< 5
            inspect(range)
        }
        """)
    }

    @Test func testCompile_openEndRangeInterfaceMembers() throws {
        try assertKotlinCompilesToKIR("""
        fun inspect(range: OpenEndRange<Int>): Boolean {
            return range.contains(3) && !range.isEmpty()
        }

        fun main() {
            val range: OpenEndRange<Int> = 1 ..< 5
            inspect(range)
        }
        """)
    }
}
#endif
