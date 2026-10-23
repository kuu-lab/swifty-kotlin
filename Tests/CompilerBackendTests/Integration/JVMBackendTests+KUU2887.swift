#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func m11WhenSubjectRangeMembershipBranches() throws {
        try withWorkspace { root in
            let source = """
            fun subject(): Int {
                println("subject")
                return 3
            }
            fun main() {
                println(when (val x = subject()) { in 1..5 -> "in"; else -> "out" })
                println(when (6) { !in 1..5 -> "outside"; else -> "inside" })
                println(when (3) { !in 1..5 -> "outside"; else -> "inside" })
            }
            """
            let expected = "subject\nin\noutside\ninside\n"
            let runtime = try m11Runtime()
            for mode in [EmitMode.jvmClass, .jvmJar] {
                let result = try compile(source, root: root, mode: mode)
                let diagnostics = result.1.map(\.message).joined(separator: "\n")
                try #require(result.0 == 0, Comment(rawValue: diagnostics))

                let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
                let execution = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
                #expect(execution.stdout == expected)
                #expect(execution.stderr.isEmpty)
            }
        }
    }
}
#endif
