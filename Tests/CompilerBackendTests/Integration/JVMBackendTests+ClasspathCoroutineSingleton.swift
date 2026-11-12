#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedCoroutineSingletonUsesDependencyInstance() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package kotlinx.coroutines
            import kotlin.coroutines.AbstractCoroutineContextElement
            import kotlin.coroutines.CoroutineContext
            object FixtureKey : CoroutineContext.Key<NonCancellable>
            object NonCancellable : AbstractCoroutineContextElement(FixtureKey) {
                override fun toString(): String = "dependency instance"
            }
            open class FixtureLoop : AbstractCoroutineContextElement(FixtureKey) {
                val isActive: Boolean get() = false
            }
            val CoroutineContext.isActive: Boolean get() = true
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import kotlin.coroutines.CoroutineContext
            import kotlinx.coroutines.FixtureLoop
            import kotlinx.coroutines.NonCancellable
            import kotlinx.coroutines.isActive
            fun main() {
                val context: CoroutineContext = NonCancellable
                println(context.toString())
                println(context.isActive)
                println(FixtureLoop().isActive)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "dependency instance\ntrue\nfalse\n")
        }
    }
}
#endif
