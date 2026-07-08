@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenArrayForLoopIteratesAllArrayTypes() throws {
        let source = """
        fun sumInts(values: IntArray): Int {
            var total = 0
            for (v in values) {
                total += v
            }
            return total
        }

        fun main() {
            for (x in arrayOf(10, 20, 30)) {
                println(x)
            }

            val strings = arrayOf("a", "b", "c")
            for (x in strings) {
                println(x)
            }

            for (x in intArrayOf(1, 2, 3)) {
                println(x)
            }

            val ints = intArrayOf(4, 5, 6)
            for (x in ints) {
                println(x)
            }

            val squares = IntArray(4) { it * it }
            for (x in squares) {
                println(x)
            }

            for (x in byteArrayOf(1, 2, 3)) {
                println(x)
            }

            for (x in longArrayOf(100L, 200L)) {
                println(x)
            }

            for (x in doubleArrayOf(1.5, 2.5)) {
                println(x)
            }

            for (x in booleanArrayOf(true, false)) {
                println(x)
            }

            for (x in charArrayOf('x', 'y')) {
                println(x)
            }

            for (x in shortArrayOf(7, 8)) {
                println(x)
            }

            for (x in intArrayOf()) {
                println("should not print: $x")
            }
            println("empty-ok")

            println(sumInts(intArrayOf(1, 2, 3, 4)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayForLoopIteration",
            expected:
                """
                10
                20
                30
                a
                b
                c
                1
                2
                3
                4
                5
                6
                0
                1
                4
                9
                1
                2
                3
                100
                200
                1.5
                2.5
                true
                false
                x
                y
                7
                8
                empty-ok
                10
                """ + "\n"
        )
    }

    func testCodegenArrayForLoopRewritesRangeIteratorToListIterator() throws {
        let source = """
        fun sumArray(values: IntArray): Int {
            var total = 0
            for (v in values) {
                total += v
            }
            return total
        }

        fun firstOfArrayOf(): Int {
            var first = -1
            for (v in arrayOf(9, 8, 7)) {
                first = v
                break
            }
            return first
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ArrayForLoopRewrite", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            for functionName in ["sumArray", "firstOfArrayOf"] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                XCTAssertTrue(callees.contains("kk_list_iterator"), "\(functionName) should call kk_list_iterator")
                XCTAssertFalse(callees.contains("kk_range_iterator"), "\(functionName) should not leave kk_range_iterator unrewritten")
            }
        }
    }
}
