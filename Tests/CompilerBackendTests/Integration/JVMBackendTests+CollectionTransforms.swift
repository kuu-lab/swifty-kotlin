#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func collectionTransformsResolveAndRunOnJVM() throws {
        try withWorkspace { root in
            let source = """
            fun main() {
                println(listOf(listOf(1, 2), listOf(3)).flatMap { it })
                println(listOf(1, 2, 3).mapNotNull { if (it > 1) it else null })
                println(listOf(1, null, 3).filterNotNull())
                println(listOf(1, 2, 3).distinctBy { it % 2 })
                println(listOf(1, 2, 3).mapIndexed { i, v -> i * v })
            }
            """
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: "app.jar"
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let runtime = try m11Runtime()
            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool(
                "kotlinc",
                ["Main.kt", "-d", "reference.jar"],
                root: root
            )
            let reference = try java([
                "-cp",
                root.appendingPathComponent("reference.jar").path + ":" + runtime,
                "MainKt",
            ])
            #expect(candidate.stdout == reference.stdout)
            #expect(candidate.stdout == "[1, 2, 3]\n[2, 3]\n[1, 3]\n[1, 2]\n[0, 2, 6]\n")
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif
