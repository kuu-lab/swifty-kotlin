#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func closedFloatingPointRangesSupportContains(mode: EmitMode) throws {
        let runtime = try m11Runtime()
        try withWorkspace { root in
            let result = try compile("""
            fun main() {
                println((1.0..2.0).contains(1.5))
                println((1.0..2.0).contains(2.5))
                println((1.0f..2.0f).contains(1.5f))
                println((1.0f..2.0f).contains(2.5f))
                println((2.0..1.0).isEmpty())
                println((2.0f..1.0f).isEmpty())
                val doubleRange = 1.0..2.0
                val floatRange = 1.0f..2.0f
                println(doubleRange.contains(2.0))
                println(floatRange.contains(2.0f))
            }
            """, root: root, mode: mode, classpath: runtime.components(separatedBy: ":"))
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + runtime, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "true\nfalse\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
