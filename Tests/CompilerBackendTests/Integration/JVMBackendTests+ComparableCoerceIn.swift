#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func comparableCoerceInLinksKotlinAndJvmCallers() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            fun precompiled(): String = "b".coerceIn("c", null)
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.precompiled
            data class Rank(val value: Int) : Comparable<Rank> {
                override fun compareTo(other: Rank): Int = value.compareTo(other.value)
            }
            fun main() {
                println(precompiled())
                println(Rank(1).coerceIn(Rank(2), Rank(4)).value)
                println(Rank(3).coerceIn(null, null).value)
                println(Rank(5).coerceIn(null, Rank(4)).value)
                println(5L.coerceIn(1L, 4L))
                try {
                    Rank(3).coerceIn(Rank(4), Rank(2))
                } catch (_: IllegalArgumentException) {
                    println("rejected")
                }
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "c\n2\n3\n4\n4\nrejected\n")
        }
    }
}
#endif
