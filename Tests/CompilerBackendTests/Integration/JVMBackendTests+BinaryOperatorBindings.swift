#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func resolvedBinaryOperatorsPreserveSourceAndInlineCalls(mode: EmitMode) throws {
        let source = """
        operator fun Char.plus(other: Char): Int = this.code + other.code + 17
        operator fun Char.times(other: Int): Int = this.code * other + 7
        operator fun Char.div(other: Int): Int = this.code / other + 11
        operator fun Char.rem(other: Int): Int = this.code % other + 13
        operator fun Int.plus(other: Char): Int = this + other.code + 19
        operator fun Char.plus(other: String): Int = this.code + other.length
        class Action
        operator fun Action.plus(other: Action) { print("U") }
        data class Vec(val x: Int) { operator fun times(n: Int) = Vec(x * n) }
        operator fun Int.times(v: Vec) = v * this
        operator inline fun <reified T: Number> T.minus(other: T): T = this
        inline fun <reified T: Number> subtract(a: T, b: T): T = a - b
        fun left(): Char { print("L"); return 'a' }
        fun right(): Int { print("R"); return 2 }
        fun main() {
            println('a' + 'b'); println('a'.plus('b'))
            println('a' * 2); println('a'.times(2))
            println('a' / 2); println('a'.div(2))
            println('a' % 2); println('a'.rem(2))
            println(2 + 'a'); println(2.plus('a'))
            println('a' + "bc"); println('a'.plus("bc"))
            println(3 * Vec(4)); println(3.times(Vec(4)))
            println(subtract(3, 1)); println(subtract(3L, 1L))
            println(left() * right())
            println('a' + 2); println('a' - 'b'); println(2 + 3); println(7.5 / 2.5)
            Action() + Action(); println(); Action().plus(Action()); println()
        }
        """
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "212\n212\n201\n201\n59\n59\n14\n14\n118\n118\n99\n99\nVec(x=12)\nVec(x=12)\n3\n3\nLR201\nc\n-1\n5\n3.0\nU\nU\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
