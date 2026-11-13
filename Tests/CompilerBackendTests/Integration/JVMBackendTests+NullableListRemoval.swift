#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func nullableListRemovalMatchesPrecompiledKotlin() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
                fun main() {
                    val items = mutableListOf<String?>(null, "left", "right")
                    println(items.removeFirstOrNull())
                    println(items.size)
                    println(items.removeLastOrNull())
                    println(items.removeFirstOrNull())
                    println(items.removeFirstOrNull())
                    println(items.removeLastOrNull())
                }
                """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            _ = try jvmTool("kotlinc", ["Main.kt", "-d", "precompiled.jar"], root: root)
            for consumer in [app, root.appendingPathComponent("precompiled.jar")] {
                let run = try java(["-Xverify:all", "-cp", consumer.path + ":" + stdlib.path, "MainKt"])
                #expect(run.stdout == "null\n2\nright\nleft\nnull\nnull\n")
                #expect(run.stderr.isEmpty)
            }
        }
    }
}
#endif
