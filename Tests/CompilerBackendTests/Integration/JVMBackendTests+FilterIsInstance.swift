#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func reifiedIterableFilteringKeepsOrderAndNullableMatches() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            interface Marker
            class Entry(val name: String) : Marker
            inline fun <reified T> selected(values: Iterable<*>): List<T> = values.filterIsInstance<T>()
            fun main() {
                val values: List<Any?> = listOf(Entry("first"), "keep", null, Entry("second"), 4)
                println(values.filterIsInstance<Entry>().map { it.name }.joinToString())
                println(selected<String?>(values).joinToString())
                println(selected<Int>(values).joinToString())
            }
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path])
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "MainKt"])
            #expect(run.stdout == "first, second\nkeep, null\n4\n")
        }
    }
}
#endif
