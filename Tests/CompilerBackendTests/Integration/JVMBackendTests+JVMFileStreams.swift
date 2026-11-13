#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmFileParentConstructorAndDirectoryMembersReachTheJdk() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            import java.io.File

            fun main(args: Array<String>) {
                val folder = File(File(args[0]), "nested")
                println(folder.mkdirs())
                println(folder.absolutePath.endsWith("nested"))
                val noParent = File(null as File?, "relative")
                println(noParent.path)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [library.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + library.path, "MainKt", root.path])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "true\ntrue\nrelative\n")
        }
    }
}
#endif
