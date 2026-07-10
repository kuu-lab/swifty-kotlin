@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenLogicalOrShortCircuitsWhenLhsIsTrue() throws {
        let source = """
        fun sideEffect(): Boolean {
            println("SIDE EFFECT EVALUATED")
            return true
        }

        fun main() {
            val result = true || sideEffect()
            println("result=$result")
        }
        """

        try assertKotlinOutput(source, moduleName: "LogicalOrShortCircuitTrue", expected: "result=true\n")
    }

    func testCodegenLogicalAndShortCircuitsWhenLhsIsFalse() throws {
        let source = """
        fun sideEffect(): Boolean {
            println("SIDE EFFECT EVALUATED")
            return true
        }

        fun main() {
            val result = false && sideEffect()
            println("result=$result")
        }
        """

        try assertKotlinOutput(source, moduleName: "LogicalAndShortCircuitFalse", expected: "result=false\n")
    }

    func testCodegenLogicalOrEvaluatesRhsWhenLhsIsFalse() throws {
        let source = """
        fun sideEffect(): Boolean {
            println("SIDE EFFECT EVALUATED")
            return true
        }

        fun main() {
            val result = false || sideEffect()
            println("result=$result")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LogicalOrEvaluatesRhsWhenNeeded",
            expected: "SIDE EFFECT EVALUATED\nresult=true\n"
        )
    }

    func testCodegenLogicalAndEvaluatesRhsWhenLhsIsTrue() throws {
        let source = """
        fun sideEffect(): Boolean {
            println("SIDE EFFECT EVALUATED")
            return false
        }

        fun main() {
            val result = true && sideEffect()
            println("result=$result")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LogicalAndEvaluatesRhsWhenNeeded",
            expected: "SIDE EFFECT EVALUATED\nresult=false\n"
        )
    }

    // Regression test: `list.isEmpty() || list.last() == x` must not evaluate
    // `list.last()` when the list is already empty, or it throws NoSuchElementException.
    func testCodegenLogicalOrShortCircuitAvoidsNoSuchElementException() throws {
        let source = """
        fun main() {
            val stack = mutableListOf<String>()
            val result = stack.isEmpty() || stack.last() == ".."
            println("result=$result")
        }
        """

        try assertKotlinOutput(source, moduleName: "LogicalOrAvoidsListLastCrash", expected: "result=true\n")
    }

    // Regression test: `s.length >= 2 && s[1] == x` must not evaluate `s[1]`
    // when the length guard already fails, or it throws an out-of-bounds exception.
    func testCodegenLogicalAndShortCircuitAvoidsStringIndexOutOfBounds() throws {
        let source = """
        fun main() {
            val s = "a"
            val result = s.length >= 2 && s[1] == ':'
            println("result=$result")
        }
        """

        try assertKotlinOutput(source, moduleName: "LogicalAndAvoidsStringIndexCrash", expected: "result=false\n")
    }

    func testCodegenChainedLogicalAndShortCircuitsAtFirstFalse() throws {
        let source = """
        fun t(tag: String): Boolean { println("eval $tag"); return true }
        fun f(tag: String): Boolean { println("eval $tag"); return false }

        fun main() {
            val result = t("a") && f("b") && t("c")
            println("result=$result")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ChainedLogicalAndShortCircuit",
            expected: "eval a\neval b\nresult=false\n"
        )
    }

    func testCodegenChainedLogicalOrShortCircuitsAtFirstTrue() throws {
        let source = """
        fun t(tag: String): Boolean { println("eval $tag"); return true }
        fun f(tag: String): Boolean { println("eval $tag"); return false }

        fun main() {
            val result = f("a") || t("b") || t("c")
            println("result=$result")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ChainedLogicalOrShortCircuit",
            expected: "eval a\neval b\nresult=true\n"
        )
    }

    func testCodegenLogicalAndInIfConditionKeepsSmartCastAndShortCircuits() throws {
        let source = """
        fun main() {
            val s: String? = null
            if (s != null && s.length > 0) {
                println("non-empty")
            } else {
                println("null-or-empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "LogicalAndInIfConditionSmartCast", expected: "null-or-empty\n")
    }
}
