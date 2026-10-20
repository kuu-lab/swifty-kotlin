#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibAlsoPreservesReceiverAndNonLocalReturns(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            var calls = 0
            fun source(): String { calls++; return "value" }
            fun returned(): Int { 7.also { return it + 1 }; return 0 }
            fun main() {
                val value = source().also { println(it) }.also { println(it.length) }
                println(value)
                println(calls)
                val empty: String? = null
                println(empty.also { println(it == null) } == null)
                println(returned())
                val callback: (Int) -> Unit = { println(it * 2) }
                println(9.also(callback))
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "value\n5\nvalue\n1\ntrue\ntrue\n8\n18\n9\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
