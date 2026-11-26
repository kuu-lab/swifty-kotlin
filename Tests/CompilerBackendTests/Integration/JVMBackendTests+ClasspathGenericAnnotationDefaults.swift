#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedAnnotationDefaultsNameGenericClassesWithoutStarArguments() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture

            import kotlin.reflect.KClass

            interface Codec<T>

            annotation class Kind<T>

            annotation class Marked(
                val codec: KClass<*> = Codec::class,
                val kind: Kind<*> = Kind<Nothing>(),
            )

            fun describe(): String = "marked"
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.Marked
            import fixture.describe

            @Marked
            class Local

            fun main() {
                println(describe())
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "marked\n")
        }
    }
}
#endif
