#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedSuspendExtensionAcceptsComposableContent() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let compose = try composeJVMFixture(root, stdlib: stdlib)
            let bridge = """
            package fixture;
            import androidx.compose.runtime.Composer;
            import kotlin.Unit;
            import kotlin.jvm.functions.Function2;
            public class SuspendContentBridge {
                @SuppressWarnings("unchecked")
                public static void render(Object body) {
                    ((Function2<Composer, Integer, Unit>) body).invoke(Bridge.COMPOSER, 0);
                }
            }
            """
            try bridge.write(to: root.appendingPathComponent("SuspendContentBridge.java"), atomically: true, encoding: .utf8)
            let fixtureClasspath = [compose.path, stdlib.path].joined(separator: ":")
            let driver = try jvmTool("javac", ["--release", "8", "-cp", fixtureClasspath, "-d", "provider", "SuspendContentBridge.java"], root: root)
            try #require(driver.exitCode == 0, "\(driver.stderr)")
            let source = """
            package fixture
            import androidx.compose.runtime.Composable
            class Widget
            suspend fun Widget.render(content: @Composable () -> Unit) {
                SuspendContentBridge.render(content)
            }
            """
            try source.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let provider = root.appendingPathComponent("provider")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-cp", fixtureClasspath + ":" + provider.path, "-d", provider.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let facade = provider.appendingPathComponent("fixture/ProviderKt.class")
            var classfile = try Data(contentsOf: facade)
            let ordinaryCarrier = Data("kotlin/jvm/functions/Function0".utf8)
            let composeCarrier = Data("kotlin/jvm/functions/Function2".utf8)
            try #require(classfile.range(of: ordinaryCarrier) != nil)
            // Model the Compose plugin's erased ABI while retaining Kotlin's logical function type.
            while let range = classfile.range(of: ordinaryCarrier) {
                classfile.replaceSubrange(range, with: composeCarrier)
            }
            try classfile.write(to: facade)
            let packed = try jvmTool("jar", ["cf", "provider.jar", "-C", provider.path, "."], root: root)
            try #require(packed.exitCode == 0, "\(packed.stderr)")

            let appSource = """
            import androidx.compose.runtime.Composable
            import fixture.Widget
            import fixture.render
            import kotlin.coroutines.*

            @Composable fun Leaf() { println("rendered") }

            class Done : Continuation<Unit> {
                override val context: CoroutineContext get() = EmptyCoroutineContext
                override fun resumeWith(result: Result<Unit>) { result.getOrThrow() }
            }

            fun main() {
                val work: suspend () -> Unit = { Widget().render { Leaf() } }
                work.startCoroutine(Done())
            }
            """
            let classpath = [root.appendingPathComponent("provider.jar").path, compose.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", appSource)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "rendered\n")
        }
    }
}
#endif
