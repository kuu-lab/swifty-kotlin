#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinCompanionsRetainTheirTypeAndValueProperties() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            @JvmInline value class Pixels(val raw: Float) {
                companion object {
                    val Bold: Pixels get() = Pixels(8f)
                    fun name(): String = "pixels"
                    @JvmStatic fun unit(): String = "px"
                }
            }
            interface Modifier {
                fun apply(value: Int): Int
                companion object : Modifier {
                    override fun apply(value: Int): Int = value + 1
                }
            }
            fun Modifier.padding(pixels: Pixels): Float = apply(pixels.raw.toInt()).toFloat()
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import api.Modifier
            import api.Pixels
            import api.padding
            fun main() {
                println(Modifier.padding(Pixels.Bold))
                println(Pixels.name())
                println(Pixels.Companion.unit())
            }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "9.0\npixels\npx\n")
        }
    }
}
#endif
