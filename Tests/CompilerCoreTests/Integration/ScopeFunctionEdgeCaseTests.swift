#if canImport(Testing)
import Foundation
import Testing

// STDLIB-002: Scope function edge case coverage.
// Covers: let / run / with / apply / also / takeIf / takeUnless
@Suite struct ScopeFunctionEdgeCaseTests {

    // MARK: - STDLIB-002-01: let returns block result (not receiver)

    @Test func testLetReturnsBlockResult() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n: Int = "hello".let { it.length }
            println(n)
        }
        """, moduleName: "STDLIB002_01")
    }

    // MARK: - STDLIB-002-02: run (extension) returns block result; this == receiver

    @Test func testExtensionRunReturnsBlockResult() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val len: Int = "world".run { length }
            println(len)
        }
        """, moduleName: "STDLIB002_02")
    }

    // MARK: - STDLIB-002-03: with returns block result; receiver exposed as this

    @Test func testWithReturnsBlockResult() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val upper: String = with("hello") { uppercase() }
            println(upper)
        }
        """, moduleName: "STDLIB002_03")
    }

    // MARK: - STDLIB-002-04: apply returns receiver (not block result)

    @Test func testApplyReturnsReceiver() throws {
        try assertKotlinCompilesToKIR("""
        class Cfg { var x: Int = 0 }
        fun main() {
            val c: Cfg = Cfg().apply { x = 42 }
            println(c.x)
        }
        """, moduleName: "STDLIB002_04")
    }

    // MARK: - STDLIB-002-05: also returns receiver (block receives it)

    @Test func testAlsoReturnsReceiver() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s: String = "kotlin".also { println(it) }
            println(s.length)
        }
        """, moduleName: "STDLIB002_05")
    }

    // MARK: - STDLIB-002-06: takeIf returns receiver when predicate true; null otherwise

    @Test func testTakeIfReturnsReceiverOnTrue() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val pos: Int? = 5.takeIf { it > 0 }
            val neg: Int? = (-1).takeIf { it > 0 }
            println(pos)
            println(neg)
        }
        """, moduleName: "STDLIB002_06")
    }

    // MARK: - STDLIB-002-07: takeUnless returns receiver when predicate false; null otherwise

    @Test func testTakeUnlessReturnsReceiverOnFalse() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val blankStr: String? = "".takeUnless { it.isEmpty() }
            val nonBlank: String? = "hi".takeUnless { it.isEmpty() }
            println(blankStr)
            println(nonBlank)
        }
        """, moduleName: "STDLIB002_07")
    }

    // MARK: - STDLIB-002-08: null receiver short-circuit with ?.let

    @Test func testNullReceiverLetShortCircuits() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s: String? = null
            val result: Int? = s?.let { it.length }
            println(result)
        }
        """, moduleName: "STDLIB002_08")
    }

    // MARK: - STDLIB-002-09: ?.let on non-null value executes block

    @Test func testNonNullReceiverLetExecutesBlock() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s: String? = "hello"
            val result: Int? = s?.let { it.length }
            println(result)
        }
        """, moduleName: "STDLIB002_09")
    }

    // MARK: - STDLIB-002-10: nested scope functions (let inside run)

    @Test func testNestedScopeFunctions() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result: Int = run {
                "hello".let { it.length }
            }
            println(result)
        }
        """, moduleName: "STDLIB002_10")
    }

    // MARK: - STDLIB-002-11: takeIf chained with let

    @Test func testTakeIfChainedWithLet() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val value: String? = "kotlin"
                .takeIf { it.startsWith("kot") }
                ?.let { it.uppercase() }
            println(value)
        }
        """, moduleName: "STDLIB002_11")
    }

    // MARK: - STDLIB-002-12: takeUnless chained with takeIf

    @Test func testTakeUnlessChainedWithTakeIf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val value: String? = "kotlin"
                .takeUnless { it.length > 10 }
                ?.takeIf { it.isNotEmpty() }
            println(value)
        }
        """, moduleName: "STDLIB002_12")
    }

    // MARK: - STDLIB-002-13: top-level run returns block result

    @Test func testTopLevelRunReturnsBlockResult() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val v: Int = run { 42 }
            println(v)
        }
        """, moduleName: "STDLIB002_13")
    }

    // MARK: - STDLIB-002-14: apply used for builder pattern (mutation + return)

    @Test func testApplyBuilderPattern() throws {
        try assertKotlinCompilesToKIR("""
        class Builder {
            var name: String = ""
            var value: Int = 0
        }
        fun main() {
            val b = Builder().apply {
                name = "test"
                value = 7
            }
            println(b.name)
            println(b.value)
        }
        """, moduleName: "STDLIB002_14")
    }

    // MARK: - STDLIB-002-15: also for logging side-effect without mutating chain

    @Test func testAlsoForSideEffect() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val doubled = 21
                .also { println("before: $it") }
                .let { it * 2 }
                .also { println("after: $it") }
            println(doubled)
        }
        """, moduleName: "STDLIB002_15")
    }

    // MARK: - STDLIB-002-16: with used for multi-statement block on object

    @Test func testWithMultiStatementBlock() throws {
        try assertKotlinCompilesToKIR("""
        class Point(var x: Int, var y: Int)
        fun main() {
            val p = Point(3, 4)
            val dist: Int = with(p) {
                val sq = x * x + y * y
                sq
            }
            println(dist)
        }
        """, moduleName: "STDLIB002_16")
    }

    // MARK: - STDLIB-002-17: run extension — this-qualified member access

    @Test func testExtensionRunThisQualifiedMember() throws {
        try assertKotlinCompilesToKIR("""
        class Counter(var count: Int = 0) {
            fun inc() { count++ }
        }
        fun main() {
            val c = Counter()
            val v = c.run {
                inc()
                inc()
                count
            }
            println(v)
        }
        """, moduleName: "STDLIB002_17")
    }

    // MARK: - STDLIB-002-18: takeIf with false predicate produces null (no receiver)

    @Test func testTakeIfFalsePredicateProducesNull() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val r: Int? = 0.takeIf { it != 0 }
            println(r ?: -1)
        }
        """, moduleName: "STDLIB002_18")
    }

    // MARK: - STDLIB-002-19: takeUnless with true predicate produces null

    @Test func testTakeUnlessTruePredicateProducesNull() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val r: Int? = 0.takeUnless { it == 0 }
            println(r ?: -1)
        }
        """, moduleName: "STDLIB002_19")
    }

    // MARK: - STDLIB-002-20: let block with explicit it parameter name shadowing

    @Test func testLetExplicitItParameterName() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val len: Int = "hello".let { s -> s.length }
            println(len)
        }
        """, moduleName: "STDLIB002_20")
    }

    // MARK: - STDLIB-002-21: apply returns receiver type (not Unit)

    @Test func testApplyTypeIsReceiver() throws {
        try assertKotlinCompilesToKIR("""
        class Box(var v: Int)
        fun mutate(b: Box): Box = b.apply { v = v * 2 }
        fun main() {
            val b = Box(5)
            val result = mutate(b)
            println(result.v)
        }
        """, moduleName: "STDLIB002_21")
    }

    // MARK: - STDLIB-002-22: also receives it (not this); explicit it reference

    @Test func testAlsoReceivesItNotThis() throws {
        try assertKotlinCompilesToKIR("""
        class Wrapper(val value: Int)
        fun main() {
            val w = Wrapper(10).also { wrapper ->
                println(wrapper.value)
            }
            println(w.value)
        }
        """, moduleName: "STDLIB002_22")
    }

    // MARK: - STDLIB-002-23: scope function inside if expression

    @Test func testScopeFunctionInsideIfExpression() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val flag = true
            val result = if (flag) {
                "yes".let { it.uppercase() }
            } else {
                "no".let { it.uppercase() }
            }
            println(result)
        }
        """, moduleName: "STDLIB002_23")
    }

    // MARK: - STDLIB-002-24: let returns null-typed result (block returns null)

    @Test func testLetBlockReturnsNull() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val r: String? = "hello".let { null }
            println(r)
        }
        """, moduleName: "STDLIB002_24")
    }

    // MARK: - STDLIB-002-25: run (top-level) in a loop accumulator

    @Test func testTopLevelRunInLoop() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            var sum = 0
            for (i in 1..5) {
                sum += run { i * i }
            }
            println(sum)
        }
        """, moduleName: "STDLIB002_25")
    }
}
#endif
