#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedSuspendInterfaceKeepsGenericParameterTypes() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            class Reminder(val text: String)
            interface Scheduler {
                suspend fun reschedule(reminders: List<Reminder>?): Int
            }
            suspend fun invoke(scheduler: Scheduler): Int =
                scheduler.reschedule(listOf(Reminder("DroidKaigi"))) + scheduler.reschedule(null)
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.*
            class Impl : Scheduler {
                override suspend fun reschedule(reminders: List<Reminder>?): Int =
                    reminders?.first()?.text?.length ?: 1
            }
            suspend fun main() {
                val scheduler: Scheduler = Impl()
                println(invoke(scheduler))
                println(scheduler.reschedule(listOf(Reminder("hi"))))
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "11\n2\n")
        }
    }
}
#endif
