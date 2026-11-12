#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedFinalMethodKeepsGenericResultAndNullability() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            class Stream<T>(val item: T)
            open class Base {
                open fun existing(): Stream<String> = Stream("parent")
            }
            class Reader : Base() {
                fun reminders(): Stream<String?> = Stream("DroidKaigi")
                override fun existing(): Stream<String> = Stream("child")
            }
            fun <T> Stream<T>.first(): T = item
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.*
            fun main() { println(Reader().reminders().first()?.length) }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "10\n")
            let rejected = """
            import fixture.*
            fun reject(): Int = Reader().reminders().first().length
            """
            let (_, rejectExit, _) = try m22Build(root: root, sources: [("Reject.kt", rejected)], name: "reject.jar", classpath: classpath)
            #expect(rejectExit == 1)
        }
    }
}
#endif
