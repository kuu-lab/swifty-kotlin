#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func charPredicatesResolveAndExecuteOnJVM() throws {
        let library = try ownStdlibLibrary()
        let source = """
        fun main() {
            println('A'.isLetter())
            println('1'.isDigit())
            println(' '.isWhitespace())
            println('7'.isLetterOrDigit())
            println('A'.isLetterOrDigit())
            println('!'.isLetterOrDigit())
        }
        """
        let expected = "true\ntrue\ntrue\ntrue\ntrue\nfalse\n"
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: .jvmJar, root: root)

            let javaSource = """
            public class JavaCharPredicateConsumer {
                public static void main(String[] args) {
                    System.out.println(kotlin.text.CharsKt.isLetter('A'));
                    System.out.println(kotlin.text.CharsKt.isLetterOrDigit('A'));
                    System.out.println(kotlin.text.CharsKt.isLetterOrDigit('7'));
                    System.out.println(kotlin.text.CharsKt.isLetterOrDigit('!'));
                }
            }
            """
            try javaSource.write(to: root.appendingPathComponent("JavaCharPredicateConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-cp", library.path, "JavaCharPredicateConsumer.java"], root: root)
            let javaExecution = try java(["-cp", root.path + ":" + library.path, "JavaCharPredicateConsumer"])
            #expect(javaExecution.stdout == "true\ntrue\ntrue\nfalse\n")
            #expect(javaExecution.stderr.isEmpty)
        }
    }
}
#endif
