#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedInterfaceMethodsKeepStableParameterNames() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture
            interface Scheduler { fun register(start: Long, end: Long, title: String, place: String): String }
            fun scheduler(): Scheduler = object : Scheduler {
                override fun register(start: Long, end: Long, title: String, place: String): String = "$title/$place/$start/$end"
            }
            """.write(to: root.appendingPathComponent("CalendarFixture.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency.jar").path
            let compiled = try jvmTool("kotlinc", ["CalendarFixture.kt", "-d", dependency], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [dependency, library.path]
            let source = """
            import fixture.scheduler
            fun main() { println(scheduler().register(place = "room", end = 9L, title = "talk", start = 7L)) }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "talk/room/7/9\n")
        }
    }
}
#endif
