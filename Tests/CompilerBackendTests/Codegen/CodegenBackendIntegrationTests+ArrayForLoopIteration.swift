@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// DEBT-KIR-005: `for (x in array)` silently never executed the loop body
// because arrays have no real `iterator()` member for Sema to bind, so
// lowering fell through to the range-iterator intrinsics and misread the
// array object as a range (hasNext() always false).
extension CodegenBackendIntegrationTests {

    func testByteArrayForLoopIteration() throws {
        let source = """
        fun main() {
            for (b in "HI".encodeToByteArray()) {
                println(b)
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "ByteArrayForLoopIteration", expected: "72\n73\n")
    }

    func testIntArrayForLoopIteration() throws {
        let source = """
        fun main() {
            for (x in intArrayOf(10, 20, 30)) {
                println(x)
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "IntArrayForLoopIteration", expected: "10\n20\n30\n")
    }

    func testObjectArrayForLoopIteration() throws {
        let source = """
        fun main() {
            for (s in arrayOf("a", "b", "c")) {
                println(s)
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "ObjectArrayForLoopIteration", expected: "a\nb\nc\n")
    }

    func testEmptyArrayForLoopDoesNotExecuteBody() throws {
        let source = """
        fun main() {
            for (x in IntArray(0)) {
                println(x)
            }
            println("done")
        }
        """
        try assertKotlinOutput(source, moduleName: "EmptyArrayForLoopDoesNotExecuteBody", expected: "done\n")
    }

    func testArrayForLoopContinueAndBreak() throws {
        let source = """
        fun main() {
            for (x in intArrayOf(1, 2, 3, 4, 5)) {
                if (x == 2) continue
                if (x == 4) break
                println(x)
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "ArrayForLoopContinueAndBreak", expected: "1\n3\n")
    }

    func testByteArrayForLoopLowersToIndexBasedLoopNotRangeIterator() throws {
        let source = """
        fun main() {
            for (b in "HI".encodeToByteArray()) {
                println(b)
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try XCTUnwrap(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        XCTAssertTrue(callees.contains("kk_array_size"), "array for-loop should call kk_array_size, got: \(callees)")
        XCTAssertTrue(callees.contains("kk_array_get_inbounds"), "array for-loop should call kk_array_get_inbounds, got: \(callees)")
        XCTAssertFalse(callees.contains("kk_range_iterator"), "array for-loop must not use kk_range_iterator, got: \(callees)")
        XCTAssertFalse(callees.contains("kk_range_hasNext"), "array for-loop must not use kk_range_hasNext, got: \(callees)")
        XCTAssertFalse(callees.contains("kk_range_next"), "array for-loop must not use kk_range_next, got: \(callees)")
    }
}
