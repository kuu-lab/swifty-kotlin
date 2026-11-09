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

    @Test
    func bundledJvmValuesSatisfySerializableBoundsAndChecks() throws {
        try withWorkspace { root in
            let stdlib = try m22Build(root: root, name: "kswiftk-stdlib.jar", stdlib: true)
            try #require(stdlib.1 == 0, "\(stdlib.2.map(\.message))")

            let app = try m22Build(
                root: root,
                sources: [("Main.kt", """
            import java.io.Serializable

            fun <T : Serializable> identity(value: T): T = value

            fun main() {
                println(5 is Serializable)
                println(2.5 is Serializable)
                println("s" is Serializable)
                println(arrayOf(1) is Serializable)
                println(intArrayOf(1) is Serializable)
                println(listOf(1) is Serializable)
                println(identity(5))
            }
            """)],
                name: "serializable-app.jar",
                classpath: [stdlib.0.path]
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let execution = try java(["-cp", app.0.path + ":" + stdlib.0.path, "MainKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "true\ntrue\ntrue\ntrue\ntrue\ntrue\n5\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
