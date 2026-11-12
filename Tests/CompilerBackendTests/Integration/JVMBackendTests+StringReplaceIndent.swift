#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func replaceIndentMatchesKotlinJvmAndSupportsJavaConsumer() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = #"""
            fun main() {
                println("a\n b".replaceIndent("&gt;"))
                println("---")
                println("\n    alpha\n      beta\n   gamma\n".replaceIndent(">>"))
                println("  alpha\n\n    beta\n".replaceIndent("x"))
                println("  first\n    \n  last".replaceIndent("|").replace(" ", "_"))
                println(" \n   \n".replaceIndent("!").replace(" ", "_"))
                println("<" + "".replaceIndent(">") + ">")
                println("  default\n  value".replaceIndent())
                println("plain\n  indented\n".replaceIndent(">"))
                println("  first\r\n    second\r third\n".replaceIndent("|").replace("\n", "/"))
            }
            """#
            try source.write(to: root.appendingPathComponent("Main.kt"), atomically: true, encoding: .utf8)

            let candidate = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: "candidate.jar",
                classpath: [library.path]
            )
            try #require(candidate.1 == 0, "\(candidate.2.map(\.message))")

            let runtime = try m11Runtime()
            let candidateRun = try java(["-cp", candidate.0.path + ":" + library.path, "MainKt"])
            _ = try jvmTool("kotlinc", ["-cp", runtime, "Main.kt", "-d", "reference.jar"], root: root)
            let referenceRun = try java([
                "-cp",
                root.appendingPathComponent("reference.jar").path + ":" + runtime,
                "MainKt",
            ])
            let expected = "&gt;a\n&gt; b\n---\n>> alpha\n>>   beta\n>>gamma\nxalpha\nx\nx  beta\n|first\n|__\n|last\n!___\n<>\ndefault\nvalue\n>plain\n>  indented\n| first/|   second/|third\n"
            #expect(candidateRun.stdout == expected)
            #expect(referenceRun.stdout == expected)
            #expect(candidateRun.stdout == referenceRun.stdout)
            #expect(candidateRun.stderr.isEmpty)
            #expect(referenceRun.stderr.isEmpty)

            let javaSource = #"""
            public final class JavaConsumer {
                public static void main(String[] args) throws Exception {
                    Class<?> facade = Class.forName("kotlin.text.StringsKt");
                    java.lang.reflect.Method method = facade.getMethod("replaceIndent", String.class, String.class);
                    String value = (String) method.invoke(null, "a\n b", "&gt;");
                    System.out.println(value.replace("\n", "/"));
                }
            }
            """#
            try javaSource.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "JavaConsumer.java"], root: root)
            let javaRun = try java(["-cp", root.path + ":" + library.path, "JavaConsumer"])
            #expect(javaRun.stdout == "&gt;a/&gt; b\n")
            #expect(javaRun.stderr.isEmpty)
        }
    }

    @Test(arguments: ["null", "1"])
    func replaceIndentRejectsInvalidNewIndent(argument: String) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try m22Build(
                root: root,
                sources: [("Invalid.kt", "fun main() { println(\"text\".replaceIndent(\(argument))) }")],
                name: "invalid.jar",
                classpath: [library.path]
            )
            #expect(result.1 != 0)
            let messages = result.2.map(\.message).joined(separator: "\n").lowercased()
            #expect(!messages.contains("unresolved member function 'replaceindent'"))
            #expect(messages.contains("argument type mismatch"))
        }
    }
}
#endif
