#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinEnumStaticsMatchKotlinc() throws {
        try withWorkspace { root in
            try """
            package fixture
            enum class Plain { ALPHA, BETA }
            enum class WithCompanion {
                ONE, TWO;
                companion object { fun tag() = "tag" }
            }
            enum class WithOverload {
                FALLBACK, OTHER;
                companion object {
                    fun valueOf(name: String, fallback: WithOverload): WithOverload = fallback
                }
            }
            """.write(to: root.appendingPathComponent("Enums.kt"), atomically: true, encoding: .utf8)
            let enums = root.appendingPathComponent("enums.jar").path
            let compiled = try jvmTool("kotlinc", ["Enums.kt", "-d", enums], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import fixture.Plain
            import fixture.WithCompanion
            import fixture.WithOverload
            fun main() {
                println(Plain.values().size)
                println(Plain.valueOf("BETA") == Plain.BETA)
                println(Plain.entries.size)
                println(WithCompanion.values().size)
                println(WithCompanion.valueOf("TWO") == WithCompanion.TWO)
                println(WithCompanion.entries.size)
                println(WithCompanion.tag())
                println(WithOverload.valueOf("missing", WithOverload.FALLBACK) == WithOverload.FALLBACK)
            }
            """
            try source.write(to: root.appendingPathComponent("Main.kt"), atomically: true, encoding: .utf8)
            let runtime = try m11Runtime()
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [enums])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path, enums, runtime]).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "2\ntrue\n2\n2\ntrue\n2\ntag\ntrue\n")

            _ = try jvmTool("kotlinc", ["-cp", ([enums, runtime]).joined(separator: ":"), "Main.kt", "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", ([root.appendingPathComponent("reference.jar").path, enums, runtime]).joined(separator: ":"), "MainKt"])
            #expect(reference.exitCode == 0, "\(reference.stderr)")
            #expect(reference.stdout == run.stdout)
        }
    }
}
#endif
