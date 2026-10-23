#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func enumRelationalOperatorsCompareOrdinals(mode: EmitMode) throws {
        try assertJVM("""
        enum class Direction { NORTH, SOUTH, WEST }
        fun main() {
            println(Direction.NORTH < Direction.SOUTH)
            println(Direction.SOUTH > Direction.NORTH)
            println(Direction.NORTH <= Direction.NORTH)
            println(Direction.SOUTH >= Direction.WEST)
            println(Direction.NORTH.compareTo(Direction.SOUTH))
        }
        """, "true\ntrue\ntrue\nfalse\n-1\n", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func comparableOperatorsUseSignedCompareToResults(mode: EmitMode) throws {
        let source = """
        class Rank(val n: Int): Comparable<Rank> {
            override fun compareTo(other: Rank): Int = (n - other.n) * 11
        }
        class Direct(val n: Int) {
            operator fun compareTo(other: Direct): Int = (n - other.n) * 13
        }
        class Extension(val n: Int)
        operator inline fun Extension.compareTo(other: Extension): Int = (n - other.n) * 17
        fun <T: Comparable<T>> compare(a: T, b: T) {
            println(a < b); println(a <= b); println(a > b); println(a >= b)
        }
        fun left(): Rank { print("L"); return Rank(1) }
        fun right(): Rank { print("R"); return Rank(2) }
        fun main() {
            compare(1, 2); compare("b", "a"); compare(Rank(3), Rank(3))
            println(Direct(1) < Direct(2)); println(Extension(2) > Extension(1))
            println(left() < right())
            println(1 < 2); println("b" > "a")
            val nan = 0.0 / 0.0
            println(nan < 1.0); println(nan >= 1.0); println(nan != nan)
        }
        """
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "true\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\ntrue\nfalse\ntrue\nfalse\ntrue\ntrue\ntrue\nLRtrue\ntrue\ntrue\nfalse\nfalse\ntrue\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
