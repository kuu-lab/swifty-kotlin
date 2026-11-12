#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmMultifileClassAcceptsSingleFileFacade() throws {
        try withWorkspace { root in
            let output = try m22Build(
                root: root,
                sources: [("Case.kt", """
                @file:JvmName("WaveFacade")
                @file:JvmMultifileClass
                fun main() { println("ok") }
                """)],
                name: "case.jar"
            )
            try #require(output.1 == 0, "\(output.2.map(\.message))")

            let runtime = try m11Runtime()
            let execution = try java(["-cp", output.0.path + ":" + runtime, "WaveFacade"])
            #expect(execution.stdout == "ok\n")
            #expect(execution.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["Case.kt", "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "WaveFacade"])
            #expect(reference.stdout == execution.stdout)
            #expect(reference.stderr.isEmpty)
        }
    }

    @Test
    func jvmMultifileClassSharesFacadeAcrossSourcesAndMatchesKotlinc() throws {
        try withWorkspace { root in
            let sources = [
                ("First.kt", #"""
                @file:JvmName("WaveFacade")
                @file:JvmMultifileClass
                package wave

                fun main() { println(first() + second()) }
                fun first(): String = "one-"
                """#),
                ("Second.kt", #"""
                @file:JvmName("WaveFacade")
                @file:JvmMultifileClass
                package wave

                fun second(): String = "two"
                """#),
            ]
            let output = try m22Build(root: root, sources: sources, name: "multifile.jar")
            try #require(output.1 == 0, "\(output.2.map(\.message))")

            let runtime = try m11Runtime()
            let candidate = try java(["-cp", output.0.path + ":" + runtime, "wave.WaveFacade"])
            #expect(candidate.stdout == "one-two\n")
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["First.kt", "Second.kt", "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "wave.WaveFacade"])
            #expect(reference.stdout == candidate.stdout)
            #expect(reference.stderr.isEmpty)

            let javaSource = """
            public class JavaConsumer {
                public static void main(String[] args) {
                    System.out.println(wave.WaveFacade.first() + wave.WaveFacade.second());
                }
            }
            """
            let javaFile = root.appendingPathComponent("JavaConsumer.java")
            let classes = root.appendingPathComponent("java-classes")
            try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
            try javaSource.write(to: javaFile, atomically: true, encoding: .utf8)
            _ = try javac(["--release", "8", "-cp", output.0.path, "-d", classes.path, javaFile.path])
            let consumer = try java(["-cp", classes.path + ":" + output.0.path + ":" + runtime, "JavaConsumer"])
            #expect(consumer.stdout == "one-two\n")
            #expect(consumer.stderr.isEmpty)
        }
    }

    @Test
    func jvmNameWithoutMultifileClassKeepsItsFacade() throws {
        try withWorkspace { root in
            let output = try m22Build(
                root: root,
                sources: [("Legacy.kt", """
                @file:JvmName("LegacyFacade")
                package legacy

                fun greeting(): String = "hello"
                """)],
                name: "legacy.jar"
            )
            try #require(output.1 == 0, "\(output.2.map(\.message))")

            let javaSource = """
            public class LegacyConsumer {
                public static void main(String[] args) {
                    System.out.println(legacy.LegacyFacade.greeting());
                }
            }
            """
            let javaFile = root.appendingPathComponent("LegacyConsumer.java")
            let classes = root.appendingPathComponent("legacy-java-classes")
            try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
            try javaSource.write(to: javaFile, atomically: true, encoding: .utf8)
            _ = try javac(["--release", "8", "-cp", output.0.path, "-d", classes.path, javaFile.path])
            let runtime = try m11Runtime()
            let consumer = try java(["-cp", classes.path + ":" + output.0.path + ":" + runtime, "LegacyConsumer"])
            #expect(consumer.stdout == "hello\n")
            #expect(consumer.stderr.isEmpty)
        }
    }

    @Test
    func jvmMultifileClassRejectsMissingJvmNameAndUnmarkedSibling() throws {
        try withWorkspace { root in
            let missingName = try m22Build(
                root: root,
                sources: [("MissingName.kt", """
                @file:JvmMultifileClass
                fun main() {}
                """)],
                name: "missing-name.jar"
            )
            #expect(missingName.1 != 0)
            #expect(missingName.2.contains { $0.message.contains("requires @file:kotlin.jvm.JvmName") })

            let mixedSiblings = try m22Build(
                root: root,
                sources: [
                    ("Marked.kt", """
                    @file:JvmName("SharedFacade")
                    @file:JvmMultifileClass
                    fun marked(): String = "marked"
                    """),
                    ("Unmarked.kt", """
                    @file:JvmName("SharedFacade")
                    fun unmarked(): String = "unmarked"
                    """),
                ],
                name: "mixed-siblings.jar"
            )
            #expect(mixedSiblings.1 != 0)
            #expect(mixedSiblings.2.contains { $0.message.contains("Duplicate JVM file facade name") })
        }
    }
}
#endif
