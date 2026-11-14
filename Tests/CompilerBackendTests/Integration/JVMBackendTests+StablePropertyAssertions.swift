#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func aNonNullAssertionNarrowsAStableProperty() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            data class Entry(val values: List<Int>?)
            fun Entry.items(): List<Int> {
                val first = values!![0]
                val second = values[1]
                return listOf(first, second)
            }
            fun main() = println(Entry(listOf(1, 2)).items().joinToString())
            """
            let classpath = [stdlib.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "1, 2\n")

            let rejected = """
            class Entry(var values: List<Int>?)
            fun Entry.bad(): Int {
                values!![0]
                return values[1]
            }
            """
            let (_, failure, errors) = try m22Build(
                root: root, sources: [("Reject.kt", rejected)], name: "reject.jar", classpath: classpath
            )
            #expect(failure != 0)
            #expect(errors.contains { $0.severity == .error })
        }
    }
}
#endif
