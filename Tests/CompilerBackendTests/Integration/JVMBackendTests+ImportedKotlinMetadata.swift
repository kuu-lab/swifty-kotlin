#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importsKotlinReceiverLambdasAndDefaults() throws {
        try withWorkspace { root in
            try """
            package dependency

            class Settings { var enabled: Boolean = false }

            fun configure(block: Settings.() -> Unit): Boolean = Settings().apply(block).enabled

            interface Report {
                val enabled: Boolean

                companion object {
                    operator fun invoke(block: Settings.() -> Unit): Report {
                        val state = Settings().apply(block)
                        return object : Report { override val enabled = state.enabled }
                    }
                }
            }

            fun greeting(name: String = "world"): String = "Hello, $name"

            fun Settings.label(): String = if (enabled) "enabled" else "disabled"
            """.write(to: root.appendingPathComponent("Library.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Library.kt", "-d", "library.jar"], root: root)
            let library = root.appendingPathComponent("library.jar").path
            let result = try compile("""
            import dependency.Report
            import dependency.Settings
            import dependency.configure
            import dependency.greeting
            import dependency.label

            fun main() {
                println(configure { enabled = true })
                println(Report { enabled = true }.enabled)
                println(greeting())
                println(Settings().label())
            }
            """, root: root, mode: .jvmJar, classpath: [library])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + library + ":" + m11Runtime(), "HelloKt"])
            #expect(execution.stdout == "true\ntrue\nHello, world\ndisabled\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
