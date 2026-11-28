#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedWithContextUsesSuspendReceiverCallback() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package kotlinx.coroutines
            import kotlin.coroutines.CoroutineContext
            interface CoroutineScope { val coroutineContext: CoroutineContext }
            suspend fun <T> withContext(context: CoroutineContext, block: suspend CoroutineScope.() -> T): T =
                block(object : CoroutineScope { override val coroutineContext = context })
            """
            try provider.write(to: root.appendingPathComponent("Builders.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Builders.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import kotlinx.coroutines.withContext
            import kotlin.coroutines.EmptyCoroutineContext
            suspend fun main() {
                val result: String = withContext(EmptyCoroutineContext) {
                    if (coroutineContext === EmptyCoroutineContext) "same context" else "wrong context"
                }
                println(result)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "same context\n")
        }
    }

    @Test
    func importedMultifileWithContextKeepsFunctionTypes() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let scopePart = """
            @file:JvmMultifileClass
            @file:JvmName("BuildersKt")
            package kotlinx.coroutines
            import kotlin.coroutines.CoroutineContext
            interface CoroutineScope { val coroutineContext: CoroutineContext }
            """
            let functionsPart = """
            @file:JvmMultifileClass
            @file:JvmName("BuildersKt")
            package kotlinx.coroutines
            import kotlin.coroutines.CoroutineContext
            suspend fun <T> withContext(context: CoroutineContext, block: suspend CoroutineScope.() -> T): T =
                block(object : CoroutineScope { override val coroutineContext = context })
            suspend fun <T> CoroutineScope.withCtx(block: suspend CoroutineScope.() -> T): T = block(this)
            """
            try scopePart.write(to: root.appendingPathComponent("Builders.kt"), atomically: true, encoding: .utf8)
            try functionsPart.write(to: root.appendingPathComponent("Builders.common.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Builders.kt", "Builders.common.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import kotlinx.coroutines.CoroutineScope
            import kotlinx.coroutines.withContext
            import kotlinx.coroutines.withCtx
            import kotlin.coroutines.CoroutineContext
            import kotlin.coroutines.EmptyCoroutineContext

            class MyScope(override val coroutineContext: CoroutineContext) : CoroutineScope

            suspend fun main() {
                val scope = MyScope(EmptyCoroutineContext)
                val topLevel: String = withContext(EmptyCoroutineContext) {
                    if (coroutineContext === EmptyCoroutineContext) "context-ok" else "wrong context"
                }
                val extension: Int = scope.withCtx {
                    if (coroutineContext === EmptyCoroutineContext) 42 else 0
                }
                println(topLevel)
                println(extension)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "context-ok\n42\n")
        }
    }

    @Test
    func importedContextFunctionsKeepTopLevelAndFacadeCallsAligned() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            @file:JvmName("ContextApi")
            package fixture

            context(prefix: String)
            fun append(suffix: String): String = prefix + suffix
            """
            try provider.write(to: root.appendingPathComponent("ContextApi.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["-Xcontext-parameters", "ContextApi.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
                import fixture.ContextApi
                import fixture.append

                fun main() {
                    println(with("top-") { append("level") })
                    println(ContextApi.append("facade-", "member"))
                }
                """
            let classpath = [library.path, own.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "top-level\nfacade-member\n")
        }
    }
}
#endif
