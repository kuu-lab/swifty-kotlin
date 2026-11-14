#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledArrayElementAccessLinksAgainstOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val values = arrayOf(null, "last")
                println(values.firstOrNull())
                println(values.lastOrNull())
                println(values.first())
                println(values.last())
                println(values.getOrNull(-1))
                println(floatArrayOf(-0.0f, 2.0f).firstOrNull())
                println(floatArrayOf(1.0f, 2.0f).last())
                println(floatArrayOf().lastOrNull())
                println(intArrayOf(5).first())
                println(intArrayOf().getOrNull(0))
                println(intArrayOf(9, 2, 5).min())
                println(intArrayOf(9, 2, 5).max())
                println(intArrayOf().minOrNull())
                println(floatArrayOf(0f, -0f).min())
                println(floatArrayOf(-0f, 0f).max())
                println(floatArrayOf(2f, Float.NaN).min())
                try {
                    emptyArray<String>().first()
                } catch (error: NoSuchElementException) {
                    println(error.message)
                }
            }
            """
            try source.write(to: root.appendingPathComponent("Elements.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Elements.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let args = ["-Xverify:all", "-cp"]
            let reference = try java(args + [app.path + ":" + (try m11Runtime()), "ElementsKt"])
            let run = try java(args + [app.path + ":" + stdlib.path, "ElementsKt"])
            #expect(run.stdout == reference.stdout)
        }
    }
}
#endif
