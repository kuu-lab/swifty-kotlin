#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedMemberExtensionUsesLogicalValueClassReceiver() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            @JvmInline value class Dp(val value: Float)
            @JvmInline value class Sp(val value: Float)
            interface Density {
                fun Dp.toPx(): Float = value * 2f
                fun Sp.toPx(): Float = value * 3f
            }
            fun density(): Density = object : Density {}
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-jvm-default=no-compatibility", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.*
            fun main() {
                println(with(density()) { Dp(4f).toPx() })
                println(with(density()) { Sp(4f).toPx() })
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "8.0\n12.0\n")
        }
    }
}
#endif
