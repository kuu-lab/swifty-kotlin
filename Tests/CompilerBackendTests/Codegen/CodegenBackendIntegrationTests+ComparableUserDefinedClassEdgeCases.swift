@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenComparisonOperatorsDispatchUserDefinedCompareToThroughGenericBound() throws {
        let source = """
        class Version(val major: Int, val minor: Int) : Comparable<Version> {
            override fun compareTo(other: Version): Int {
                val byMajor = major.compareTo(other.major)
                return if (byMajor != 0) byMajor else minor.compareTo(other.minor)
            }
        }

        fun <T : Comparable<T>> larger(a: T, b: T): T = if (a >= b) a else b

        fun main() {
            val v1 = Version(1, 2)
            val v2 = Version(1, 5)
            println(v1 < v2)
            println(v1 > v2)
            println(larger(v1, v2).minor)
            println(larger(v2, v1).minor)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparisonOperatorsUserDefinedCompareToThroughGenericBound",
            expected:
                """
                true
                false
                5
                5

                """
        )
    }

    func testCodegenComparableMaxOfMinOfDispatchUserDefinedCompareTo() throws {
        let source = """
        class Version(val major: Int, val minor: Int) : Comparable<Version> {
            override fun compareTo(other: Version): Int {
                val byMajor = major.compareTo(other.major)
                return if (byMajor != 0) byMajor else minor.compareTo(other.minor)
            }
            override fun toString(): String = "$major.$minor"
        }

        fun main() {
            val v1 = Version(1, 2)
            val v2 = Version(1, 5)
            println(maxOf(v1, v2))
            println(minOf(v1, v2))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparableMaxOfMinOfUserDefinedCompareTo",
            expected:
                """
                1.5
                1.2

                """
        )
    }
}
