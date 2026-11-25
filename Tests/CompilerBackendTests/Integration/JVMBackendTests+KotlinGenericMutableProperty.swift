#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func kotlinClasspathRetainsGenericMutablePropertyAccessors() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let library = """
            package fixture
            fun group(): Group = Group(listOf("start"))
            class Group(var values: List<String>) {
                var readOnlyHere: List<String> = listOf("fixed")
                    private set
            }
            """
            try library.write(to: root.appendingPathComponent("Group.kt"), atomically: true, encoding: .utf8)
            let reference = try jvmTool("kotlinc", ["Group.kt", "-jvm-target", "1.8", "-d", "dependency.jar"], root: root)
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let dependency = root.appendingPathComponent("dependency.jar")
            let main = """
            import fixture.group
            fun main() {
                val group = group()
                println(group.values.first().uppercase())
                group.values = listOf("next")
                println(group.values.first().uppercase())
                println(group.readOnlyHere.first().uppercase())
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", main)], name: "app.jar", classpath: [dependency.path, stdlib.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", [app.path, dependency.path, stdlib.path].joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "START\nNEXT\nFIXED\n")
        }
    }
}
#endif
