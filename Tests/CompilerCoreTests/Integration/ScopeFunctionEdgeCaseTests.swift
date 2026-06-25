@testable import CompilerCore
import Foundation
import XCTest

final class ScopeFunctionEdgeCaseTests: XCTestCase {

    func testLetReturnsBlockResult() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n: Int = "hello".let { it.length }
            println(n)
        }
        """, moduleName: "STDLIB002_01")
    }

    func testExtensionRunReturnsBlockResult() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val len: Int = "world".run { length }
            println(len)
        }
        """, moduleName: "STDLIB002_02")
    }

    func testWithReturnsBlockResult() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val upper: String = with("hello") { uppercase() }
            println(upper)
        }
        """, moduleName: "STDLIB002_03")
    }

    func testApplyReturnsReceiver() throws {
        try assertKotlinCompilesToKIR("""
        class Cfg { var x: Int = 0 }
        fun main() {
            val c: Cfg = Cfg().apply { x = 42 }
            println(c.x)
        }
        """, moduleName: "STDLIB002_04")
    }

    func testAlsoReturnsReceiver() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s: String = "kotlin".also { println(it) }
            println(s.length)
        }
        """, moduleName: "STDLIB002_05")
    }

    func testTakeIfReturnsReceiverOnTrue() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val pos: Int? = 5.takeIf { it > 0 }
            val neg: Int? = (-1).takeIf { it > 0 }
            println(pos)
            println(neg)
        }
        """, moduleName: "STDLIB002_06")
    }

    func testTakeUnlessReturnsReceiverOnFalse() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val blankStr: String? = "".takeUnless { it.isEmpty() }
            val nonBlank: String? = "hi".takeUnless { it.isEmpty() }
            println(blankStr)
            println(nonBlank)
        }
        """, moduleName: "STDLIB002_07")
    }

    func testNullReceiverLetShortCircuits() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s: String? = null
            val result: Int? = s?.let { it.length }
            println(result)
        }
        """, moduleName: "STDLIB002_08")
    }

    func testNonNullReceiverLetExecutesBlock() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s: String? = "hello"
            val result: Int? = s?.let { it.length }
            println(result)
        }
        """, moduleName: "STDLIB002_09")
    }

    func testNestedScopeFunctions() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result: Int = run {
                "hello".let { it.length }
            }
            println(result)
        }
        """, moduleName: "STDLIB002_10")
    }

    func testTakeIfChainedWithLet() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val value: String? = "kotlin"
                .takeIf { it.startsWith("kot") }
                ?.let { it.uppercase() }
            println(value)
        }
        """, moduleName: "STDLIB002_11")
    }

    func testTakeUnlessChainedWithTakeIf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val value: String? = "kotlin"
                .takeUnless { it.length > 10 }
                ?.takeIf { it.isNotEmpty() }
            println(value)
        }
        """, moduleName: "STDLIB002_12")
    }

    func testTopLevelRunReturnsBlockResult() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val v: Int = run { 42 }
            println(v)
        }
        """, moduleName: "STDLIB002_13")
    }

    func testApplyBuilderPattern() throws {
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

    func testAlsoForSideEffect() throws {
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

    func testWithMultiStatementBlock() throws {
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

    func testExtensionRunThisQualifiedMember() throws {
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

    func testTakeIfFalsePredicateProducesNull() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val r: Int? = 0.takeIf { it != 0 }
            println(r ?: -1)
        }
        """, moduleName: "STDLIB002_18")
    }

    func testTakeUnlessTruePredicateProducesNull() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val r: Int? = 0.takeUnless { it == 0 }
            println(r ?: -1)
        }
        """, moduleName: "STDLIB002_19")
    }

    func testLetExplicitItParameterName() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val len: Int = "hello".let { s -> s.length }
            println(len)
        }
        """, moduleName: "STDLIB002_20")
    }

    func testApplyTypeIsReceiver() throws {
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

    func testAlsoReceivesItNotThis() throws {
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

    func testScopeFunctionInsideIfExpression() throws {
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

    func testLetBlockReturnsNull() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val r: String? = "hello".let { null }
            println(r)
        }
        """, moduleName: "STDLIB002_24")
    }

    func testTopLevelRunInLoop() throws {
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
