#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func resolvedUnaryOperatorsPreserveUnsignedExtensionsAndControls(mode: EmitMode) throws {
        let source = """
        operator fun UByte.unaryMinus(): Int = 11
        operator fun UShort.unaryMinus(): Int = 12
        operator fun UInt.unaryMinus(): Int = 13
        operator fun ULong.unaryMinus(): Int = 14
        operator fun UByte.unaryPlus(): Int = 21
        operator fun UShort.unaryPlus(): Int = 22
        operator fun UInt.unaryPlus(): Int = 23
        operator fun ULong.unaryPlus(): Int = 24

        fun operand(): UInt {
            println("operand")
            return 1u
        }

        fun unsignedMain() {
            val ub: UByte = 1u
            val us: UShort = 1u
            val ui: UInt = 1u
            val ul: ULong = 1uL
            println(-ub)
            println(-us)
            println(-ui)
            println(-ul)
            println(-1u)
            println(-1uL)
            println(-operand())
            println(+ub)
            println(+us)
            println(+ui)
            println(+ul)
            println(+1u)
            println(+1uL)
            println(-1)
            println(-1L)
            println(-1.5f)
            println(-1.5)
            println(0u - 1u)
            println(0uL - 1uL)
        }

        data class Vector(val x: Int) { operator fun unaryMinus() = Vector(-x) }
        class Action
        operator fun Action.not() { print("U") }
        class Token(val number: Int)
        inline operator fun Token.unaryMinus(): Int { print("I"); return -this.number }
        fun token(): Token { print("T"); return Token(3) }
        fun main() {
            unsignedMain()
            println((-Vector(4)).x); println(Vector(4).unaryMinus().x)
            println(-token()); println(token().unaryMinus())
            !Action(); println()
            println(1u.unaryMinus()); println(1u.unaryPlus())
            println(!false); println(-2147483648)
        }
        """
        let expected = "11\n12\n13\n14\n13\n14\noperand\n13\n21\n22\n23\n24\n23\n24\n-1\n-1\n-1.5\n-1.5\n4294967295\n18446744073709551615\n-4\n-4\nTI-3\nTI-3\nU\n13\n23\ntrue\n-2147483648\n"
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-d", "official.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("official.jar").path + ":" + library.path, "HelloKt"])
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif
