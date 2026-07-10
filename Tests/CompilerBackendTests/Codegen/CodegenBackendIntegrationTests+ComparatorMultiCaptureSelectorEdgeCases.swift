@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// Follow-up to the closure-capture ABI fix in
/// CallLowerer+ClosureAdapters.swift: selector lambdas passed to
/// compareBy/compareValuesBy go through makeCollectionHOFSelectorArgument,
/// whose captureArguments were previously forwarded via the raw-only
/// makeClosureRawArgument instead of makeClosureRawOrBoxedArgument. A
/// selector capturing 2+ distinct locals would silently drop everything
/// but the first capture. These tests lock in the fix for all three
/// affected call sites (vararg compareBy/compareValuesBy selectors via
/// appendCollectionHOFSelectorPair, and the compareValuesBy(a, b, comparator)
/// { selector } path).
extension CodegenBackendIntegrationTests {
    func testCodegenCompilesCompareByVarargSelectorsWithMultiCaptureSelector() throws {
        let source = """
        fun main() {
            val hundredsDiv: Int = 100
            val tensBonus: Int = 3
            val cmp = compareBy<Int>(
                { x -> x / hundredsDiv + tensBonus },
                { x -> x % 100 / 10 },
                { x -> x % 10 },
                { x -> -x }
            )
            println(listOf(231, 132, 121, 221).sortedWith(cmp))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CompareByVarargMultiCaptureSelector",
            expected: "[121, 132, 221, 231]\n"
        )
    }

    func testCodegenCompilesCompareValuesByVarargSelectorsWithMultiCaptureSelector() throws {
        let source = """
        fun main() {
            val hundredsDiv: Int = 100
            val tensBonus: Int = 3
            println(compareValuesBy(231, 132,
                { x -> x / hundredsDiv + tensBonus },
                { x -> x % 100 / 10 },
                { x -> x % 10 },
                { x -> -x }
            ))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareValuesByVarargMultiCaptureSelector", expected: "1\n")
    }

    func testCodegenCompilesCompareValuesByComparatorSelectorWithMultiCaptureSelector() throws {
        let source = """
        fun main() {
            val mul: Int = 10
            val off: Int = 1
            val ascending = compareBy<Int> { it }
            println(compareValuesBy(13, 25, ascending) { x -> x % mul + off })
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareValuesByComparatorMultiCaptureSelector", expected: "-1\n")
    }
}
