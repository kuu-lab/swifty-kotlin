#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinExtensionPropertiesBridgeTheirValueClassCarrier() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            @JvmInline value class Pixels(val raw: Float)
            val Int.pixels: Pixels get() = Pixels(toFloat())
            val Long.pixels: Pixels get() = Pixels(toFloat() + 1f)
            val baseline: Pixels get() = Pixels(2f)
            fun raw(pixels: Pixels): Float = pixels.raw
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import api.pixels
            import api.raw
            import api.baseline
            fun main() {
                println(raw(4.pixels))
                println(raw(4L.pixels))
                println(raw(baseline))
            }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "4.0\n5.0\n2.0\n")
        }
    }
}
#endif
