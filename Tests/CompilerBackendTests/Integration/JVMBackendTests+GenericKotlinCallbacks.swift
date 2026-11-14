#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func kotlinClasspathKeepsGenericMemberCallbackTypes() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let library = """
            package fixture
            class Box<T>(val value: T)
            fun words(): Box<List<String>> = Box(listOf("item"))
            fun count(): Box<Int> = Box(5)
            object Combining {
                fun <A, B, R> run(a: Box<A>, b: Box<B>, transform: (A, B) -> R): Box<R> =
                    Box(transform(a.value, b.value))
            }
            """
            try library.write(to: root.appendingPathComponent("Combining.kt"), atomically: true, encoding: .utf8)
            let reference = try jvmTool("kotlinc", ["Combining.kt", "-jvm-target", "1.8", "-d", "dependency.jar"], root: root)
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let dependency = root.appendingPathComponent("dependency.jar")
            let main = """
            import fixture.Combining
            import fixture.words
            import fixture.count
            fun main() {
                val result = Combining.run(words(), count()) { values, count ->
                    values.first() + count
                }
                println(result.value)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", main)], name: "app.jar", classpath: [dependency.path, stdlib.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", [app.path, dependency.path, stdlib.path].joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "item5\n")
        }
    }
}
#endif
