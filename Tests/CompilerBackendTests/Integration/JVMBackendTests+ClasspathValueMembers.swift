#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func classpathPropertiesUseMangledGettersAndValueReceivers() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            @JvmInline value class Pixels(val raw: Float)
            @JvmInline value class Size(val packed: Long) {
                val width: Pixels get() = Pixels(packed.toFloat())
            }
            class Layout(val size: Size)
            fun layout(): Layout = Layout(Size(24L))
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import api.layout
            fun main() { println(layout().size.width.raw) }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "24.0\n")
        }
    }
}

extension JVMBackendTests {
    @Test
    func classpathMemberExtensionsUseTheDispatchAndExtensionReceivers() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            interface Scope {
                fun String.label(): String
            }
            fun measure(content: Scope.() -> String): String {
                val scope = object : Scope {
                    override fun String.label(): String = "scope " + this
                }
                return scope.content()
            }
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import api.measure
            fun main() { println(measure { "value".label() }) }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "scope value\n")
        }
    }
}
#endif
