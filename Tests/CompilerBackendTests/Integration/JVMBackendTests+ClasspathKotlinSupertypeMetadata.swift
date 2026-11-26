#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func classpathKotlinSupertypeKeepsMetadataArguments() throws {
        try withWorkspace { root in
            let fixture = root.appendingPathComponent("Fixture.kt")
            try """
                package fixture

                abstract class JsonArrayLike : List<String>
                """.write(to: fixture, atomically: true, encoding: .utf8)
            let kotlinc = try jvmTool("kotlinc", ["Fixture.kt", "-d", "fixture.jar"], root: root)
            try #require(kotlinc.exitCode == 0, "\(kotlinc.stderr)")

            // The java.util import makes the JDK image reader pull java/util/*
            // into the classpath index, so java/util/List is visible.
            let consumer = """
                import fixture.JsonArrayLike
                import java.util.Objects

                fun probe(v: JsonArrayLike) {
                    v.forEach { println(it.length) }
                    println(Objects.requireNonNull("x"))
                }
                """
            let (_, exitCode, diagnostics) = try m22Build(
                root: root,
                sources: [("Consumer.kt", consumer)],
                name: "consumer.jar",
                classpath: [root.appendingPathComponent("fixture.jar").path]
            )
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
        }
    }

    @Test
    func classpathKotlinSupertypePreservesArgumentNullability() throws {
        try withWorkspace { root in
            let fixture = root.appendingPathComponent("NullableItems.kt")
            try """
                package fixture

                abstract class NullableItems : List<String?>
                """.write(to: fixture, atomically: true, encoding: .utf8)
            let kotlinc = try jvmTool("kotlinc", ["NullableItems.kt", "-d", "nullable.jar"], root: root)
            try #require(kotlinc.exitCode == 0, "\(kotlinc.stderr)")
            let classpath = [root.appendingPathComponent("nullable.jar").path]

            let unguarded = """
                import fixture.NullableItems
                import java.util.Objects

                fun probe(v: NullableItems) {
                    v.forEach { println(it.length) }
                    println(Objects.requireNonNull("x"))
                }
                """
            let (_, unguardedExit, unguardedDiagnostics) = try m22Build(
                root: root,
                sources: [("Unguarded.kt", unguarded)],
                name: "unguarded.jar",
                classpath: classpath
            )
            #expect(unguardedExit != 0)
            #expect(unguardedDiagnostics.contains { $0.message.contains("nullable receiver") })

            let safe = """
                import fixture.NullableItems
                import java.util.Objects

                fun probe(v: NullableItems) {
                    v.forEach { println(it?.length) }
                    println(Objects.requireNonNull("x"))
                }
                """
            let (_, safeExit, safeDiagnostics) = try m22Build(
                root: root,
                sources: [("Safe.kt", safe)],
                name: "safe.jar",
                classpath: classpath
            )
            try #require(safeExit == 0, "\(safeDiagnostics.map(\.message))")
        }
    }
}
#endif
