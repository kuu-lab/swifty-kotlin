#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func jvmEnumEntriesFindReturnsFirstMatchAndStopsInvokingPredicate() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            enum class Channel { BLOG, VIDEO, PODCAST }
            fun main() {
                var calls = 0
                println(Channel.entries.find { calls += 1; it == Channel.VIDEO })
                println(calls)
                println(Channel.entries.find { false })
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [library.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + library.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "VIDEO\n2\nnull\n")
        }
    }
}
#endif
