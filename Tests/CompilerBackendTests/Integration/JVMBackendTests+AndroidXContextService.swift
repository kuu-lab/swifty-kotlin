#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedAndroidXContextServiceUsesReifiedClassAndNullableResult() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let providers = [
                ("Context.kt", """
                package android.content
                class Context(val enabled: Boolean)
                class TestService(val name: String)
                """),
                ("ContextCompat.kt", """
                package androidx.core.content
                import android.content.Context
                import android.content.TestService

                object ContextCompat {
                    @JvmStatic
                    fun <T : Any> getSystemService(context: Context, clazz: Class<T>): T? =
                        if (context.enabled && clazz == TestService::class.java) clazz.cast(TestService("service")) else null
                }
                """),
                ("ContextExtensions.kt", """
                @file:JvmName("ContextKt")
                package androidx.core.content
                import android.content.Context

                inline fun <reified T : Any> Context.getSystemService(): T? =
                    ContextCompat.getSystemService(this, T::class.java)
                """),
            ]
            for (file, content) in providers {
                try content.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            }
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", providers.map { $0.0 } + ["-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import android.content.Context
            import android.content.TestService
            import androidx.core.content.getSystemService

            inline fun <reified T : Any> Context.findService(): T? = getSystemService<T>()
            fun main() {
                println(Context(true).getSystemService<TestService>()?.name)
                println(Context(false).findService<TestService>())
                println(Context(true).getSystemService<Int>())
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "service\nnull\nnull\n")
        }
    }
}
#endif
