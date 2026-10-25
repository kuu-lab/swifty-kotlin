#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func builtinStringAndIntAreSerializableForJvmIsChecks() throws {
        try withWorkspace { root in
            let result = try m22Build(
                root: root,
                sources: [
                    ("Serializable.kt", "package java.io\ninterface Serializable\n"),
                    ("Main.kt", """
            fun main() {
                val text: String = "x"
                val number: Int = 1
                println(text is java.io.Serializable)
                println(number is java.io.Serializable)
            }
            """)
                ],
                name: "serializable.jar",
                mode: .jvmJar
            )
            try #require(result.1 == 0, "\(result.2.map(\.message))")

            let execution = try java(["-cp", result.0.path, "MainKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "true\ntrue\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
