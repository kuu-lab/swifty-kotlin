#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func kotlinClasspathClassBoundsKeepMetadataNullability() throws {
        try withWorkspace { root in
            try """
            package dep

            class KBox<T : Number>(val value: T) {
                fun get(): T = value
            }
            """.write(to: root.appendingPathComponent("KBox.kt"), atomically: true, encoding: .utf8)
            let kotlinLibrary = root.appendingPathComponent("kbox.jar")
            let compiled = try jvmTool("kotlinc", ["KBox.kt", "-d", kotlinLibrary.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let valid = try m22Build(
                root: root,
                sources: [("Valid.kt", """
                import dep.KBox

                fun valid(): KBox<Int> = KBox(1)
                """)],
                name: "valid.jar",
                classpath: [kotlinLibrary.path]
            )
            try #require(valid.1 == 0, "\(valid.2.map(\.message))")

            let invalid = try m22Build(
                root: root,
                sources: [("Invalid.kt", """
                import dep.KBox

                fun invalid(): KBox<Int?> = KBox<Int?>(null)
                """)],
                name: "invalid.jar",
                classpath: [kotlinLibrary.path]
            )
            #expect(invalid.1 != 0)
            #expect(invalid.2.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-BOUND" })

            try """
            package dep;
            public class JBox<T extends Number> {
                private T value;
                public JBox(T value) { this.value = value; }
                public T get() { return value; }
            }
            """.write(to: root.appendingPathComponent("JBox.java"), atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("java-classes"), withIntermediateDirectories: true)
            let javac = try jvmTool("javac", ["--release", "8", "-d", "java-classes", "JBox.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let javaLibrary = root.appendingPathComponent("jbox.jar")
            let jar = try jvmTool("jar", ["cf", javaLibrary.path, "-C", "java-classes", "."], root: root)
            try #require(jar.exitCode == 0, "\(jar.stderr)")

            let javaConsumer = try m22Build(
                root: root,
                sources: [("JavaConsumer.kt", """
                import dep.JBox

                fun valid(): JBox<Int> = JBox(1)
                fun nullable(): JBox<Int?> = JBox(null)
                """)],
                name: "java-consumer.jar",
                classpath: [javaLibrary.path]
            )
            try #require(javaConsumer.1 == 0, "\(javaConsumer.2.map(\.message))")
        }
    }
}
#endif
