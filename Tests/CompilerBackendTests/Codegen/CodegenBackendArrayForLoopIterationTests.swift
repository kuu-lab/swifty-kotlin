@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

// DEBT-KIR-005: `for (x in array)` silently never executed the loop body
// because arrays have no real `iterator()` member for Sema to bind, so
// lowering fell through to the range-iterator intrinsics and misread the
// array object as a range (hasNext() always false).
@Suite
struct CodegenBackendArrayForLoopIterationTests {

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
    func testSizedInitializerPrimitiveFlavorAndNestedArrayForLoopIteration() throws {
        let source = """
        fun sumInts(values: IntArray): Int {
            var total = 0
            for (v in values) {
                total += v
            }
            return total
        }

        fun <T> firstOrNullOf(items: Array<T>): T? {
            for (item in items) {
                return item
            }
            return null
        }

        fun main() {
            for (x in IntArray(4) { it * it }) {
                println(x)
            }
            for (x in longArrayOf(100L, 200L)) {
                println(x)
            }
            for (x in doubleArrayOf(1.5, 2.5)) {
                println(x)
            }
            for (x in floatArrayOf(1.5f, 2.5f)) {
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
            for (inner in arrayOf(intArrayOf(1, 2), intArrayOf(3))) {
                for (v in inner) {
                    println(v)
                }
            }
            println(sumInts(intArrayOf(1, 2, 3, 4)))
            println(firstOrNullOf(arrayOf("p", "q")))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "SizedInitializerPrimitiveFlavorAndNestedArrayForLoopIteration",
            expected: "0\n1\n4\n9\n100\n200\n1.5\n2.5\n1.5\n2.5\ntrue\nfalse\nx\ny\n7\n8\n1\n2\n3\n10\np\n"
        )
    }

    @Test
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
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains("__kk_array_size"), "array for-loop should call __kk_array_size, got: \(callees)")
        #expect(
            callees.contains("kk_array_get_inbounds"),
            "array for-loop should call kk_array_get_inbounds, got: \(callees)"
        )
        #expect(!callees.contains("kk_range_iterator"), "array for-loop must not use kk_range_iterator, got: \(callees)")
        #expect(!callees.contains("kk_range_hasNext"), "array for-loop must not use kk_range_hasNext, got: \(callees)")
        #expect(!callees.contains("kk_range_next"), "array for-loop must not use kk_range_next, got: \(callees)")
    }
}

#endif
