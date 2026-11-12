#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedMangledMembersKeepTheirValueParameterTypes() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            @JvmInline
            value class Size(val packed: Long)
            fun size(packed: Long): Size = Size(packed)
            interface Shape {
                fun outline(size: Size): String
            }
            class Box : Shape {
                override fun outline(size: Size): String = "packed:" + size.packed
                fun outline(size: Long): String = "raw:" + size
            }
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.*
            fun main() {
                val box = Box()
                val shape: Shape = box
                println(shape.outline(size(7L)))
                println(box.outline(size = size(8L)))
                println(box.outline(9L))
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "packed:7\npacked:8\nraw:9\n")
        }
    }
}
#endif
