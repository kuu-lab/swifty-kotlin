#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func kuu4670DurationParseResolvesAndUsesPublishedJvmMethods() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            import kotlin.time.Duration

            fun main() {
                println(Duration.parse("1h30m"))
                println(Duration.parseOrNull("1e3s") == null)
                println(Duration.parseIsoStringOrNull(" PT1H ") == null)
                println(Duration.parseIsoString("PT-1H"))
                println(Duration.parseIsoString("PT4.005S"))
                println(Duration.parseOrNull("INFINITY"))
                println(Duration.parse("0.5s"))
                println(Duration.parse("-(1h 30m)"))
                println(Duration.parseOrNull("+1h 30m") == null)
            }
            """
            let expected = "1h 30m\ntrue\ntrue\n-1h\n4.005s\nInfinity\n500ms\n-(1h 30m)\ntrue\n"

            let own = try m22Build(root: root, sources: [("consumer.kt", source)], name: "own-consumer.jar", mode: .jvmJar, classpath: [library.path])
            try #require(own.1 == 0, "\(own.2.map(\.message))")
            let ownExecution = try java(["-cp", own.0.path + ":" + library.path, "ConsumerKt"])
            #expect(ownExecution.exitCode == 0, "\(ownExecution.stderr)")
            #expect(ownExecution.stdout == expected)

            try source.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["-no-stdlib", "-no-reflect", "-cp", library.path, "consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let result = try java(["-Xverify:all", "-cp", root.appendingPathComponent("consumer.jar").path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == expected)
        }
    }
}
#endif
