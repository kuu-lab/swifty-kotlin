#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func elvisEarlyExitNarrowsThroughSafeAccessAndImmutableAlias() throws {
        try withWorkspace { root in
            let main = """
            class Record(val value: String)
            class Item(val record: Record, val label: String)
            fun display(input: Any) {
                val record = (input as? Item)?.record
                val value = record?.value ?: return
                println(input.label + ":" + record.value + ":" + value)
            }
            fun main() {
                display(Item(Record("ok"), "item"))
                display(42)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", main)], name: "app.jar")
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "item:ok:ok\n")

            let rejected = """
            class Record(val value: String)
            class Item(val record: Record, val label: String)
            fun display(input: Any) {
                var current = input
                val record = (current as? Item)?.record
                current = Any()
                val value = record?.value ?: return
                println(current.label + value)
            }
            """
            let (_, status, errors) = try m22Build(root: root, sources: [("Wrong.kt", rejected)], name: "wrong.jar")
            #expect(status != 0)
            #expect(errors.contains { $0.message.contains("label") })
        }
    }
}
#endif
