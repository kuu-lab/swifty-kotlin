#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importsExternalMemberExtensionsOnFunctionTypes() throws {
        try withWorkspace { root in
            try """
            package fixture

            class Builder {
                fun (() -> String).evaluate(): String = this()
                fun render(action: () -> String): String = action.evaluate()
            }
            """.write(to: root.appendingPathComponent("Builder.kt"), atomically: true, encoding: .utf8)
            let library = try jvmTool("kotlinc", ["Builder.kt", "-d", "builder.jar"], root: root)
            try #require(library.exitCode == 0, "\(library.stderr)")

            let jar = root.appendingPathComponent("builder.jar").path
            let result = try compile("""
            import fixture.Builder

            fun main() {
                println(Builder().render { "venue" })
            }
            """, root: root, mode: .jvmJar, classpath: [jar])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let classpath = try [root.appendingPathComponent("hello.jar").path, jar, m11Runtime()].joined(separator: ":")
            let execution = try java(["-Xverify:all", "-cp", classpath, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "venue\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
