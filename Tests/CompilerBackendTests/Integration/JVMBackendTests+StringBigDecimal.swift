#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func stringToBigDecimalResolvesAndExecutes(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("""
            fun main() {
                println("1.5".toBigDecimal().toString())
                println("42".toBigDecimal().toString())
                println("1.5".toBigDecimal() > "1.4".toBigDecimal())
            }
            """, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "1.5\n42\ntrue\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
