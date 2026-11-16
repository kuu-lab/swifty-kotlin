#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedExtensionReferencesCaptureTheirReceiver() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            fun String.decorate(suffix: String): String = this + suffix
            fun String.log(): String = this
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import api.decorate
            import api.log

            fun invokeOne(callback: (String) -> String) = callback("!")
            fun invokeTwo(callback: (String, String) -> String) = callback("unbound", "?")
            fun invokeUnit(callback: () -> Unit) = callback()
            fun main() {
                val receiver = "bound"
                println(invokeOne(receiver::decorate))
                println(invokeTwo(String::decorate))
                invokeUnit(receiver::log)
                println("adapted")
            }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "bound!\nunbound?\nadapted\n")
        }
    }
}
#endif
