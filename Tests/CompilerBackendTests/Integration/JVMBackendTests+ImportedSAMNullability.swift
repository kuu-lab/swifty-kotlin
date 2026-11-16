#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinSAMAcceptsNullReferenceArgument() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture

            class Entry(val name: String)
            fun interface Listener {
                fun onChange(current: Entry, previous: Entry?)
            }
            fun notify(listener: Listener) = listener.onChange(Entry("current"), null)
            """.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let provider = try jvmTool("kotlinc", ["Provider.kt", "-d", "provider.jar"], root: root)
            try #require(provider.exitCode == 0, "\(provider.stderr)")
            let cp = [root.appendingPathComponent("provider.jar").path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", """
                import fixture.notify

                fun main() = notify { current, previous ->
                    println(current.name + "/" + (previous?.name ?: "missing"))
                }
                """)], name: "app.jar", classpath: cp
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + cp).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "current/missing\n")
        }
    }
}
#endif
