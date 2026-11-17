#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedGenericCallbackOverridesPreserveSupertypeArguments() throws {
        let runtime = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture

            interface Key<T> {
                fun initial(): (() -> T?)?
                fun preload(): (suspend () -> T?)?
                fun recover(value: T): ((Throwable) -> T)?
            }

            class StringKey : Key<String> {
                override fun initial(): (() -> String?)? = { "initial" }
                override fun preload(): (suspend () -> String?)? = { "preloaded" }
                override fun recover(value: String): ((Throwable) -> String)? = { value }
            }
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("provider.jar")
            let providerBuild = try jvmTool("kotlinc", ["Provider.kt", "-d", dependency.path], root: root)
            try #require(providerBuild.exitCode == 0, "\(providerBuild.stderr)")
            let source = """
            import fixture.Key
            import fixture.StringKey

            fun main() {
                val concrete = StringKey()
                val abstract: Key<String> = concrete
                println(concrete.initial()?.invoke())
                println(concrete.recover("recovered")?.invoke(IllegalStateException()))
                println(abstract.initial()?.invoke())
            }
            """
            let classpath = [dependency.path, runtime.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "initial\nrecovered\ninitial\n")
        }
    }
}
#endif
