#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func stringLineSequenceMatchesKotlincAndSupportsJavaConsumer() throws {
        try withWorkspace { root in
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let source = try String(
                contentsOf: repository.appendingPathComponent("Scripts/diff_cases/jvm_string_line_sequence.kt"),
                encoding: .utf8
            )
            try source.write(to: root.appendingPathComponent("hello.kt"), atomically: true, encoding: .utf8)

            let runtime = try m11Runtime()
            let app = try compile(source, root: root, mode: .jvmJar)
            try #require(app.0 == 0, "\(app.1.map(\.message))")

            let appJar = root.appendingPathComponent("hello.jar")
            let runtimeClasspath = appJar.path + ":" + runtime
            let candidate = try java(["-cp", runtimeClasspath, "HelloKt"])
            #expect(candidate.exitCode == 0)
            #expect(candidate.stdout == """
            basic:2
            lf:[a, b]
            crlf:[a, b]
            trailing:[a, b, ]
            empty-count:1
            empty-first:<>
            cr:[a, b]
            char-sequence:[one, two]
            lazy-first:first
            lazy-take:[first, second]
            lazy-repeat:[first, second, third]
            lazy-before:0
            lazy-tracked-first:first
            lazy-after-first:6

            """)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let referenceJar = root.appendingPathComponent("reference.jar")
            let reference = try java(["-cp", referenceJar.path + ":" + runtime, "HelloKt"])
            #expect(reference.exitCode == 0)
            #expect(reference.stdout == candidate.stdout)
            #expect(reference.stderr.isEmpty)

            try #"""
            import java.util.Iterator;
            import kotlin.sequences.Sequence;

            public final class LineSequenceConsumer {
                public static void main(String[] args) {
                    Sequence<String> lines = HelloKt.lineSequenceForJava("first\nsecond\nthird");
                    Iterator<String> iterator = lines.iterator();
                    System.out.println(iterator.next());
                    System.out.println(iterator.next());
                    System.out.println(iterator.hasNext());
                }
            }
            """#.write(to: root.appendingPathComponent("LineSequenceConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool(
                "javac",
                ["-cp", runtimeClasspath, "LineSequenceConsumer.java"],
                root: root
            )
            let consumer = try java(["-cp", root.path + ":" + runtimeClasspath, "LineSequenceConsumer"])
            #expect(consumer.exitCode == 0)
            #expect(consumer.stdout == "first\nsecond\ntrue\n")
            #expect(consumer.stderr.isEmpty)

            let ownLibrary = try ownStdlibLibrary()
            let ownApp = try m22Build(
                root: root,
                sources: [("hello.kt", source)],
                name: "own.jar",
                classpath: [ownLibrary.path]
            )
            try #require(ownApp.1 == 0, "\(ownApp.2.map(\.message))")
            let ownRuntimeClasspath = ownApp.0.path + ":" + ownLibrary.path
            let ownExecution = try java(["-cp", ownRuntimeClasspath, "HelloKt"])
            #expect(ownExecution.exitCode == 0)
            #expect(ownExecution.stdout == candidate.stdout)
            #expect(ownExecution.stderr.isEmpty)
            let ownConsumer = try java(["-cp", root.path + ":" + ownRuntimeClasspath, "LineSequenceConsumer"])
            #expect(ownConsumer.exitCode == 0)
            #expect(ownConsumer.stdout == "first\nsecond\ntrue\n")
            #expect(ownConsumer.stderr.isEmpty)
        }
    }

    @Test
    func rejectsStringLineSequenceWithArguments() throws {
        try withWorkspace { root in
            let result = try compile(
                "fun main() { println(\"a\\nb\".lineSequence(\"x\")) }",
                root: root,
                mode: .jvmJar
            )
            #expect(result.0 == 1)
            #expect(result.1.contains { $0.severity == .error })
            #expect(!result.1.contains { $0.code == "KSWIFTK-JVM-0001" })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }
}
#endif
