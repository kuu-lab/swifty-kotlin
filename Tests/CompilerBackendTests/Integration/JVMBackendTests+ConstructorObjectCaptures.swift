#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func objectInitializerIgnoresUnrelatedSecondaryConstructorParameters() throws {
        try withWorkspace { root in
            let source = """
            interface Listener { fun signal() }
            class Entry {
                constructor()
                constructor(other: String, extra: String) { if (other == extra) changes = 8 }
                var changes = 0
                val callback = object : Listener {
                    override fun signal() { changes += 1 }
                }
            }
            fun main() {
                val first = Entry()
                val second = Entry("a", "b")
                first.callback.signal()
                second.callback.signal()
                second.callback.signal()
                println(first.changes)
                println(second.changes)
            }
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar")
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path, "MainKt"])
            #expect(run.stdout == "1\n2\n")
        }
    }
}
#endif
