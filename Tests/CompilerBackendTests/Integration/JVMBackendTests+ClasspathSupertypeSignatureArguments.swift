#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    /// Classpath stubs must recover supertype type arguments from the classfile
    /// Signature when the Kotlin metadata supertype tables decode empty
    /// (`abstract class JsonArrayLike : List<String>` built by kotlinc).
    /// Without them the stub degrades to `List<Any>` and `forEach` lambda
    /// parameters lose their element type (Sampleable.kt SEMA-0024).
    @Test
    func classpathSupertypeKeepsSignatureArguments() throws {
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
}
#endif
