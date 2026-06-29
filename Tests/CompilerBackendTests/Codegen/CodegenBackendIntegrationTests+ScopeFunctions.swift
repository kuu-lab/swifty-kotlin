@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesScopeFunctions() throws {
        let source = """
        class Builder {
            var x: Int = 0
            var y: Int = 0
        }

        fun main() {
            println("Hello".let { it.length })
            println("Hello".run { length })
            val built = Builder().apply {
                x = 10
                y = 20
            }
            println(built.x + built.y)
            println("Hello".also { println(it.length) }.length)
            println(with("Hello") { length })
        }
        """

        try assertKotlinOutput(source, moduleName: "ScopeFunctions", expected: "5\n5\n30\n5\n5\n5\n")
    }

    func testCodegenCompilesStringBuilderAppendVarargInReceiverLambda() throws {
        let source = """
        fun buildGreeting(action: StringBuilder.() -> Unit): String {
            val sb = StringBuilder()
            sb.action()
            return sb.toString()
        }

        fun main() {
            val greeting = buildGreeting {
                append("Hello")
                append(", ")
                append("World!")
            }
            println(greeting)

            val result = with(StringBuilder()) {
                append("Kotlin ")
                append("is ")
                append("fun")
                toString()
            }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "StringBuilderAppendVarargReceiverLambda", expected: "Hello, World!\nKotlin is fun\n")
    }

    func testCodegenCompilesUIntArrayConstructorIndexingAndFactory() throws {
        let source = """
        fun main() {
            val arr = UIntArray(3) { (it * 2).toUInt() }
            arr[1] = 9u
            val extra = uintArrayOf(4u, 5u)
            println(arr.size)
            println(arr[0])
            println(arr[1])
            println(arr[2])
            println(extra[0] + extra[1])
        }
        """

        try assertKotlinOutput(source, moduleName: "UIntArrayExecutable", expected: "3\n0\n9\n4\n9\n")
    }
}

