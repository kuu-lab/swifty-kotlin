#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func listAndMapEntryDestructuringUsesBundledComponents(mode: EmitMode) throws {
        let source = """
        fun main() {
            val (a, b, c, d, e) = listOf(1, 2, 3, 4, 5)
            val entry = mapOf("a" to 1).entries.first()
            val (key, value) = entry
            println("$a$b$c$d$e$key$value")
        }
        """
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let app = try m22Build(root: root, sources: [("hello.kt", source)], name: mode == .jvmJar ? "hello.jar" : "classes", mode: mode, classpath: [library.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", app.0.path + ":" + library.path, "HelloKt"])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "12345a1\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
