#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinOperatorsKeepTheirMemberModifier() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture
            class Transition(val size: Int) {
                operator fun plus(other: Transition): Transition = Transition(size + other.size)
                fun minus(other: Transition): Transition = Transition(size - other.size)
            }
            """.write(to: root.appendingPathComponent("Transition.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency.jar").path
            let compiled = try jvmTool("kotlinc", ["Transition.kt", "-d", dependency], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [dependency, library.path]
            let source = "import fixture.Transition\nfun main() { println((Transition(3) + Transition(4)).size) }"
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "7\n")
            let rejected = "import fixture.Transition\nfun bad() = Transition(3) - Transition(4)"
            let (_, failure, _) = try m22Build(
                root: root, sources: [("Bad.kt", rejected)], name: "bad.jar", classpath: classpath
            )
            #expect(failure != 0)
        }
    }
}
#endif
