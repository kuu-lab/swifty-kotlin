#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func companionQualifierIsAValueForScopedMemberExtensions() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            interface Token { companion object : Token }
            interface Scope { fun Token.label(): String }
            fun measure(content: Scope.() -> String): String {
                val scope = object : Scope {
                    override fun Token.label(): String = "companion"
                }
                return scope.content()
            }
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import api.Token
            import api.measure
            fun main() { println(measure { Token.label() }) }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "companion\n")
        }
    }

    /// A local extension on the companion's own type must beat an outer
    /// dispatch-receiver member extension of the same name (innermost scope
    /// resolves first).
    @Test
    func localCompanionExtensionShadowsOuterMemberExtension() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            interface Token { companion object : Token }
            interface Scope { fun Token.label(): String }
            fun measure(content: Scope.() -> String): String {
                val scope = object : Scope {
                    override fun Token.label(): String = "companion"
                }
                return scope.content()
            }
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import api.Token
            import api.measure
            fun main() {
                println(measure {
                    fun Token.Companion.label(): String = "local"
                    Token.label()
                })
            }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "local\n")
        }
    }

    /// A member extension that cannot accept the call's lambda argument must
    /// not commit the candidate slot — the applicable top-level companion
    /// extension still resolves.
    @Test
    func inapplicableMemberExtensionFallsThroughToCompanionExtension() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            interface Token { companion object : Token }
            interface Scope { fun Token.label(n: Int): String }
            fun measure(content: Scope.() -> String): String {
                val scope = object : Scope {
                    override fun Token.label(n: Int): String = "companion"
                }
                return scope.content()
            }
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import api.Token
            import api.measure
            fun Token.Companion.label(block: () -> String): String = block()
            fun main() { println(measure { Token.label { "top" } }) }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "top\n")
        }
    }
}
#endif
