#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedTopLevelConstantsMatchKotlin() throws {
        try withWorkspace { root in
            let dependency = root.appendingPathComponent("routes.jar")
            let source = """
            package fixture
            const val route = "timetable"
            const val count = 12
            val runtime = "runtime"
            """
            try source.write(to: root.appendingPathComponent("Routes.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Routes.kt", "-d", dependency.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = """
            import fixture.route as destination
            import fixture.count
            import fixture.runtime

            const val combined = destination + "!"
            fun main() {
                println(combined)
                println(count)
                println(runtime)
            }
            """
            let app = try m22Build(root: root, sources: [("Main.kt", consumer)], name: "app.jar", classpath: [dependency.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let run = try java(["-cp", app.0.path + ":" + dependency.path, "MainKt"])
            #expect(run.stdout == "timetable!\n12\nruntime\n")
        }
    }
}
#endif
