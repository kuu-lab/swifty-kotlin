#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func classpathSupertypeKeepsSignatureArguments() throws {
        try withWorkspace { root in
            let fixture = root.appendingPathComponent("StringList.java")
            try """
                package fixture;
                public abstract class StringList implements java.util.List<String> {
                }
                """.write(to: fixture, atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes")
            let javac = try jvmTool("javac", ["-d", classes.path, "StringList.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let artifact = root.appendingPathComponent("stringlist.jar")
            let packaged = try jvmTool("jar", ["cf", artifact.path, "-C", classes.path, "."], root: root)
            try #require(packaged.exitCode == 0, "\(packaged.stderr)")

            // The java.util import makes the JDK image reader pull java/util/*
            // into the classpath index, so java/util/List is visible.
            let consumer = """
                import fixture.StringList
                import java.util.Objects

                fun probe(v: StringList) {
                    v.forEach { println(it.length) }
                    println(Objects.requireNonNull("x"))
                }
                """
            let (_, exitCode, diagnostics) = try m22Build(
                root: root,
                sources: [("Consumer.kt", consumer)],
                name: "consumer.jar",
                classpath: [artifact.path]
            )
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
        }
    }

    @Test
    func classpathSupertypeDeduplicatesMappedInterfaces() throws {
        try withWorkspace { root in
            let fixture = root.appendingPathComponent("StringSet.java")
            try """
                package fixture;
                public abstract class StringSet implements java.util.Set<String>, java.util.SequencedSet<String> {
                }
                """.write(to: fixture, atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes")
            let javac = try jvmTool("javac", ["-d", classes.path, "StringSet.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let artifact = root.appendingPathComponent("stringset.jar")
            let packaged = try jvmTool("jar", ["cf", artifact.path, "-C", classes.path, "."], root: root)
            try #require(packaged.exitCode == 0, "\(packaged.stderr)")

            let consumer = """
                import fixture.StringSet
                import java.util.Objects

                fun probe(v: StringSet) {
                    v.forEach { println(it.length) }
                    println(Objects.requireNonNull("x"))
                }
                """
            let (_, exitCode, diagnostics) = try m22Build(
                root: root,
                sources: [("Consumer.kt", consumer)],
                name: "consumer.jar",
                classpath: [artifact.path]
            )
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
        }
    }
}
#endif
