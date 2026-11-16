#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func jvmArrayFirstOrNullAndLastIndexSupportEnumArrays() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            enum class Channel { BLOG, VIDEO }
            fun main() {
                val channels = Channel.values()
                println(channels.firstOrNull { it == Channel.VIDEO })
                println(channels.firstOrNull { false })
                println(channels.lastIndex)
                println(emptyArray<Channel>().lastIndex)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [library.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + library.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "VIDEO\nnull\n1\n-1\n")
        }
    }
}
#endif
