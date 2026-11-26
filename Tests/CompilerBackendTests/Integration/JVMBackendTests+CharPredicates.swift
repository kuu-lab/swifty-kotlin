#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func charPredicatesResolveAndExecuteOnJVM() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", """
                fun main() {
                    println('A'.isLetter())
                    println('1'.isDigit())
                    println(' '.isWhitespace())
                    println('7'.isLetterOrDigit())
                    println('A'.isLetterOrDigit())
                    println('!'.isLetterOrDigit())
                }
                """)],
                name: "app.jar",
                classpath: [library.path]
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let execution = try java(["-cp", app.0.path + ":" + library.path, "MainKt"])
            #expect(execution.stdout == "true\ntrue\ntrue\ntrue\ntrue\nfalse\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
