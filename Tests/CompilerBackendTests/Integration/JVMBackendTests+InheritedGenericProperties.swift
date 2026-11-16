#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedDelegatedPropertySubstitutesTransitiveGenericArguments() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            package api
            data class Envelope<T>(val content: T)
            fun label(envelope: Envelope<String>): String = envelope.content
            interface Key<T> {
                val id: Envelope<T>
            }
            interface NamedKey<T> : Key<T>
            class ConcreteKey : NamedKey<String> by object : NamedKey<String> {
                override val id: Envelope<String> = Envelope("session")
            }
            class ForwardingKey<T>(key: NamedKey<T>) : NamedKey<T> by key
            """
            try source.write(to: root.appendingPathComponent("Library.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Library.kt", "-d", dependency.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = """
            import api.ConcreteKey
            import api.Key
            import api.label
            fun main() {
                val key = ConcreteKey()
                println(label(key.id).uppercase())
                val interfaceKey: Key<String> = key
                println(label(interfaceKey.id))
            }
            """
            let classpath = [dependency.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", consumer)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "SESSION\nsession\n")
        }
    }
}
#endif
