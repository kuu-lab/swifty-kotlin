#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func iterableMapToInfersDestinationAndKeepsItsIdentity() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            data class Reminder(val id: String)
            fun main() {
                val reminders = listOf(Reminder("one"), Reminder("two"), Reminder("one"))
                val inferred = reminders.mapTo(mutableSetOf()) { it.id }
                println(inferred.joinToString())
                val destination = mutableListOf<CharSequence>("start")
                val returned = reminders.mapTo(destination) { it.id }
                println(returned === destination)
                println(returned.joinToString())
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "MainKt"])
            #expect(run.stdout == "one, two\ntrue\nstart, one, two, one\n")
        }
    }
}
#endif
