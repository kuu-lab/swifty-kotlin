#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func implementsImportedKotlinInterfaceDefaults() throws {
        try withWorkspace { root in
            try """
            package dependency

            interface Options {
                val label: String get() = "option"
                fun describe(value: String): String = label + " " + value
            }

            interface Detailed : Options
            """.write(to: root.appendingPathComponent("Defaults.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["-jvm-default=disable", "Defaults.kt", "-d", "defaults.jar"], root: root)
            let dependency = root.appendingPathComponent("defaults.jar").path
            let result = try compile("""
            import dependency.Detailed
            import dependency.Options

            interface Local : Detailed
            class Inherited : Local
            class Customized : Local {
                override val label = "custom"
                override fun describe(value: String): String = label + "=" + value
            }

            fun main() {
                val inherited: Options = Inherited()
                println(inherited.label)
                println(inherited.describe("value"))
                val customized: Options = Customized()
                println(customized.describe("value"))
            }
            """, root: root, mode: .jvmJar, classpath: [dependency])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java([
                "-cp", root.appendingPathComponent("hello.jar").path + ":" + dependency + ":" + m11Runtime(), "HelloKt",
            ])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "option\noption value\ncustom=value\n")
        }
    }
}
#endif
