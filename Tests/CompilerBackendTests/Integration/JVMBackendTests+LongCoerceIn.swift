#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func longCoerceInLinksPrecompiledKotlin() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
                fun main() {
                    println((-9000000000000000000L).coerceIn(-5L, 5L))
                    println(0L.coerceIn(-5L, 5L))
                    println(9000000000000000000L.coerceIn(-5L, 5L))
                    try {
                        println(0L.coerceIn(5L, -5L))
                    } catch (failure: IllegalArgumentException) {
                        println("empty range")
                    }
                }
                """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            _ = try jvmTool("kotlinc", ["Main.kt", "-d", "precompiled.jar"], root: root)
            for consumer in [app, root.appendingPathComponent("precompiled.jar")] {
                let run = try java(["-Xverify:all", "-cp", consumer.path + ":" + stdlib.path, "MainKt"])
                #expect(run.stdout == "-5\n0\n5\nempty range\n")
                #expect(run.stderr.isEmpty)
            }
        }
    }
}
#endif
