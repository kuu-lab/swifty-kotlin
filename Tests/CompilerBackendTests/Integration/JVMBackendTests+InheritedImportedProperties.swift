#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedClassImplementsKotlinInterfaceProperties() throws {
        try withWorkspace { root in
            let dependency = root.appendingPathComponent("provider.jar")
            let source = """
            package fixture
            interface Properties { val text: String }
            class Implementation : Properties { override val text = "implementation" }
            """
            try source.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let built = try jvmTool("kotlinc", ["Provider.kt", "-d", dependency.path], root: root)
            try #require(built.exitCode == 0, "\(built.stderr)")
            let consumer = """
            import fixture.Implementation
            import fixture.Properties
            fun main() {
                val concrete = Implementation()
                val abstract: Properties = concrete
                println(concrete.text)
                println(abstract.text)
            }
            """
            let app = try m22Build(root: root, sources: [("Main.kt", consumer)], name: "app.jar", classpath: [dependency.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let run = try java(["-cp", app.0.path + ":" + dependency.path, "MainKt"])
            #expect(run.stdout == "implementation\nimplementation\n")
        }
    }
}
#endif
