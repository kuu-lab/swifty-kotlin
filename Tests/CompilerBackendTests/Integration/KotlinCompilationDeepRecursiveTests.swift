#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct KotlinCompilationDeepRecursiveTests {
    @Test func testCompileDeepRecursiveFunctionBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        class Node(val next: Node?)

        fun probe(node: Node?): Int {
            val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> {
                if (it == null) 0 else callRecursive(it.next) + 1
            }
            return depth.invoke(node)
        }
        """)
    }

    @Test func testCompileDeepRecursiveFunctionExplicitParamName() throws {
        try assertKotlinCompilesToKIR("""
        class Node(val next: Node?)

        fun probe(node: Node?): Int {
            val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> { n ->
                if (n == null) 0 else callRecursive(n.next) + 1
            }
            return depth.invoke(node)
        }
        """)
    }

    // The capturing block is lowered through the receiver-aware HOF adapter
    // (closure env, scope receiver, value); without it the captured value and
    // the scope receiver share a parameter slot.
    @Test func testCompileDeepRecursiveFunctionCapturingBlock() throws {
        try assertKotlinCompilesToObject("""
        fun probe(step: Int): Int {
            val countDown = DeepRecursiveFunction<Int, Int> { n ->
                if (n <= 0) 0 else callRecursive(n - step) + 1
            }
            return countDown(9)
        }
        """)
    }

    @Test func testCompileDeepRecursiveFunctionBasicObjectEmission() throws {
        try assertKotlinCompilesToObject("""
        class Node(val next: Node?)

        fun makeDepth(): DeepRecursiveFunction<Node?, Int> {
            val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> {
                if (it == null) 0 else callRecursive(it.next) + 1
            }
            return depth
        }
        """)
    }
}
#endif
