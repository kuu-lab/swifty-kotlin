#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibUntilAndRangeAll(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            fun findFirst(): Int { (1..3).all { if (it == 2) return it; true }; return -1 }
            fun main() {
                var sum = 0
                val end = 4
                for (i in 1 until end) sum += i
                println(sum)
                val range = 2 until 5
                println(range.first); println(range.last)
                println((1 until Int.MIN_VALUE).isEmpty())
                println((Int.MAX_VALUE until Int.MAX_VALUE).isEmpty())
                var calls = 0
                println((2..5).all { calls++; it < 4 }); println(calls)
                println((1..0).all { calls++; false }); println(calls)
                println((Int.MAX_VALUE..Int.MAX_VALUE).all { it == Int.MAX_VALUE })
                println(findFirst())
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "6\n2\n4\ntrue\ntrue\nfalse\n3\ntrue\n3\ntrue\n2\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
