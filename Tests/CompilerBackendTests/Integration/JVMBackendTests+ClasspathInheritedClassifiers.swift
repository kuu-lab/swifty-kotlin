#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedInheritedClassifierShadowsDefaultImportInReturnType() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            abstract class Parent {
                class Result(val text: String)
                abstract fun work(): Result
            }
            abstract class Worker : Parent()
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.Worker
            class Task : Worker() {
                override fun work(): Result = Result("worker")
                fun standard(): kotlin.Result<String> = kotlin.Result.success("standard")
            }
            fun main() {
                println(Task().work().text)
                println(Task().standard().getOrThrow())
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "worker\nstandard\n")
        }
    }
}
#endif
