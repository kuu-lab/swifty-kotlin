@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenArrayReduceComputesSum() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.reduce { acc, x -> acc + x })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayReduce", expected: "6\n")
    }

    func testCodegenArrayReduceOrNullReturnsValueForNonEmptyArray() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.reduceOrNull { acc, x -> acc + x })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayReduceOrNull", expected: "6\n")
    }

    func testCodegenArrayReduceIndexedAccumulatesWithIndex() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            // index=1: acc=1, x=2 → 1+2*1=3
            // index=2: acc=3, x=3 → 3+3*2=9
            println(arr.reduceIndexed { index, acc, x -> acc + x * index })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayReduceIndexed", expected: "9\n")
    }

    func testCodegenArrayFoldComputesSumWithInitial() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.fold(10) { acc, x -> acc + x })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFold", expected: "16\n")
    }

    func testCodegenArrayFoldIndexedAccumulatesWithIndexAndInitial() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            // index=0: acc=0, x=1 → 0+1*0=0
            // index=1: acc=0, x=2 → 0+2*1=2
            // index=2: acc=2, x=3 → 2+3*2=8
            println(arr.foldIndexed(0) { index, acc, x -> acc + x * index })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFoldIndexed", expected: "8\n")
    }

    func testCodegenArrayFlatMapExpandsElements() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            val result = arr.flatMap { x -> listOf(x, x * 10) }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFlatMap", expected: "[1, 10, 2, 20, 3, 30]\n")
    }
}

