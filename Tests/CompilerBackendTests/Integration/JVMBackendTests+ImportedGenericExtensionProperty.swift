#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedGenericExtensionPropertiesPreserveReceiverBounds() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture
            class Wrapper<T>(private val value: T) {
                infix fun same(other: T): Boolean = value == other
            }
            val <T> T.wrapped: Wrapper<T> get() = Wrapper(this)
            val <T : CharSequence> T.copy: T get() = this
            """.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let provider = try jvmTool("kotlinc", ["Provider.kt", "-d", "provider.jar"], root: root)
            try #require(provider.exitCode == 0, "\(provider.stderr)")
            let cp = [root.appendingPathComponent("provider.jar").path, stdlib.path]
            let (app, status, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", """
                import fixture.wrapped
                import fixture.copy
                fun main() {
                    val copy: String = "item".copy
                    println(copy.wrapped same "item")
                }
                """)],
                name: "app.jar", classpath: cp
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + cp).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "true\n")
            let (_, invalid, _) = try m22Build(
                root: root,
                sources: [("Wrong.kt", "import fixture.copy\nfun main() { println(1.copy) }")],
                name: "wrong.jar", classpath: cp
            )
            #expect(invalid != 0)
        }
    }
}
#endif
